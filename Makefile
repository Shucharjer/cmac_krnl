BOARD     		?= au50
PLATFORM  		?= xilinx_u50_gen3x16_xdma_5_202210_1
TARGET    		?= hw
AXI_FREQ  		?= 300
JOBS      		?= $(shell nproc)
BUILD_DIR 		?= build
CLEAN_BUILD 	?= 1

XO       := $(BUILD_DIR)/cmac_$(BOARD).xo
SEND_XO  := $(BUILD_DIR)/send.$(TARGET).xo
RECV_XO  := $(BUILD_DIR)/recv.$(TARGET).xo
XCLBIN   := $(BUILD_DIR)/cmac_krnl.$(TARGET).$(BOARD).xclbin
HOST	 := $(BUILD_DIR)/host

VPP        := v++
VPP_COMMON := -t $(TARGET) --platform $(PLATFORM) --save-temps \
              --temp_dir $(BUILD_DIR)/_x.$(TARGET) \
              --log_dir  $(BUILD_DIR)/logs.$(TARGET) \
              --report_dir $(BUILD_DIR)/reports.$(TARGET)

CXX				:= g++
CXX_STANDARD 	:= c++20
CXX_FLAGS		:= -O2 -NDEBUG

.PHONY: all xo hls xclbin clean
all: $(XO)
xo:      $(XO)
hls:     $(SEND_XO) $(RECV_XO)
xclbin:  $(XCLBIN)
host:	 $(HOST)

# ---- CMAC RTL kernel packaged from src/ + Vivado IPs ---------------------
$(XO):
	@mkdir -p $(BUILD_DIR)
	@rm -f $(BUILD_DIR)/cmac_$(BOARD).xo
	@(date && vivado -mode batch -source scripts/pack.tcl \
	  -tclargs $(BUILD_DIR) $(BOARD) $(AXI_FREQ) $(JOBS) ) >> $(BUILD_DIR)/build.log 2>&1
	@(date && kernelinfo $(BUILD_DIR)/cmac_$(BOARD).xo) > $(BUILD_DIR)/cmac_$(BOARD).info

ifneq ($(CLEAN_BUILD), 0)
	@echo "Performing clean build..."
	@rm -rf $(BUILD_DIR)/ip \
		$(BUILD_DIR)/cmac_$(BOARD) \
		$(BUILD_DIR)/cmac_$(BOARD)_ippack
	@rm -f $(BUILD_DIR)/cmac_$(BOARD)/cmac_wrapper.v \
		$(BUILD_DIR)/cmac_$(BOARD)/kernel_qsfp*.xml
endif

# ---- HLS kernel (send.cpp) -----------------------------------------------
$(SEND_XO): hls/send.cpp
	@mkdir -p $(BUILD_DIR)
	@date >> $(BUILD_DIR)/build.log
	$(VPP) -c $(VPP_COMMON) --kernel_frequency $(AXI_FREQ) -k send $< -o $@ >> $(BUILD_DIR)/build.log 2>&1

# ---- HLS kernel (recv.cpp) -----------------------------------------------
$(RECV_XO): hls/recv.cpp
	@mkdir -p $(BUILD_DIR)
	@date >> $(BUILD_DIR)/build.log
	$(VPP) -c $(VPP_COMMON) --kernel_frequency $(AXI_FREQ) -k recv $< -o $@ >> $(BUILD_DIR)/build.log 2>&1

# ---- Full xclbin: link CMAC XO + send XO with the shell ------------------
# --kernel_frequency 300 sets ap_clk to the platform default (300 MHz) so the
# CMAC's s_axil FREQ_HZ matches the host AXI-Lite interconnect (300 MHz) and
# gets a base address. The CMAC control clock is derived inside the wrapper
# (MMCM 300->100 MHz) and is independent of ap_clk.
$(XCLBIN): $(XO) $(SEND_XO) $(RECV_XO) link/cmac_krnl.cfg
	@mkdir -p $(BUILD_DIR)
	@date >> $(BUILD_DIR)/build.log
	$(VPP) -l $(VPP_COMMON) --config link/cmac_krnl.cfg \
	  --kernel_frequency $(AXI_FREQ) \
	  $(XO) $(SEND_XO) $(RECV_XO) -o $@ >> $(BUILD_DIR)/build.log 2>&1

$(HOST): src/host.cpp
	$(CXX) -std=$(CXX_STANDARD) -I$(XILINX_XRT)/include -L$(XILINX_XRT)/lib -lxrt_coreutil \
	  $< -o $@

clean:
	rm -rf $(BUILD_DIR) vivado*.jou vivado*.log .Xil v++_*.log .ipcache analyzer_input
