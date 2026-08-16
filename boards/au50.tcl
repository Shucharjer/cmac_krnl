set board_part       xcu50-fsvh2104-2-e
set qsfp_port        0
set board_port       qsfp${qsfp_port}

# xcu50-fsvh2104 valid cmac_usplus combinations (from IP validator):
#   CMACE4_X0Y0 + X1Y0~X1Y9 / X1Y2~X1Y11 / X1Y4~X1Y13 / X1Y6~X1Y15
#   CMACE4_X0Y4 + X0Y28~X0Y31          <-- this pair maps to physical Bank 131
#                                          (QSFP0 lanes J46/G46/F44/E46 etc.)
#
# Naming caveat: X0Y28~X0Y31 is a GT CHANNEL index range, not a physical bank
# number. On xcu50 these four channels physically live in Bank 131 alongside
# QSFP0. Do NOT confuse with the "Bank 128 No Connect" note in
# boards/alveo-u50-xdc.xdc — that Bank number refers to the package's
# electrical bank labeling, not the IP's channel indexing.
set cmac_core_select CMACE4_X0Y4
set gt_group_select  X0Y28~X0Y31
set gt_ref_clk_freq  161.1328125
