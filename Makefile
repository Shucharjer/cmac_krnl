BOARD     		?= au50
PLATFORM  		?= xilinx_u50_gen3x16_xdma_5_202210_1
TARGET    		?= hw
AXI_FREQ  		?= 250
JOBS      		?= $(shell nproc)
BUILD_DIR 		?= build
CLEAN_BUILD 	?= 1

XO       := $(BUILD_DIR)/cmac_$(BOARD).xo
SEND_XO  := $(BUILD_DIR)/send.$(TARGET).xo
RECV_XO  := $(BUILD_DIR)/recv.$(TARGET).xo
XCLBIN   := $(BUILD_DIR)/cmac_krnl.$(TARGET).$(BOARD).xclbin

VPP        := v++
VPP_COMMON := -t $(TARGET) --platform $(PLATFORM) --save-temps \
              --temp_dir $(BUILD_DIR)/_x.$(TARGET) \
              --log_dir  $(BUILD_DIR)/logs.$(TARGET) \
              --report_dir $(BUILD_DIR)/reports.$(TARGET)

.PHONY: all xo hls xclbin clean
all: $(XO)
xo:      $(XO)
hls:     $(SEND_XO) $(RECV_XO)
xclbin:  $(XCLBIN)

# ---- CMAC RTL kernel packaged from src/ + Vivado IPs ---------------------
$(XO):
	@mkdir -p $(BUILD_DIR)
	@rm -f $(BUILD_DIR)/cmac_$(BOARD).xo
	@(date && vivado -mode batch -source scripts/pack.tcl \
	  -tclargs $(BUILD_DIR) $(BOARD) $(AXI_FREQ) $(JOBS) ) > $(BUILD_DIR)/build.log 2>&1
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
	$(VPP) -c $(VPP_COMMON) --kernel_frequency $(AXI_FREQ) -k send $< -o $@

# ---- HLS kernel (recv.cpp) -----------------------------------------------
$(RECV_XO): hls/recv.cpp
	@mkdir -p $(BUILD_DIR)
	$(VPP) -c $(VPP_COMMON) --kernel_frequency $(AXI_FREQ) -k recv $< -o $@

# ---- Full xclbin: link CMAC XO + send XO with the shell ------------------
# --kernel_frequency locks ap_clk == AXI_FREQ so the CMAC IP's GT_DRP_CLK
# (also = AXI_FREQ, baked into the XO by pack.tcl) matches actual ap_clk.
$(XCLBIN): $(XO) $(SEND_XO) $(RECV_XO) link/cmac_krnl.cfg
	@mkdir -p $(BUILD_DIR)
	$(VPP) -l $(VPP_COMMON) --config link/cmac_krnl.cfg \
	  --kernel_frequency $(AXI_FREQ) \
	  $(XO) $(SEND_XO) $(RECV_XO) -o $@

clean:
	rm -rf $(BUILD_DIR) vivado*.jou vivado*.log .Xil v++_*.log .ipcache analyzer_input
