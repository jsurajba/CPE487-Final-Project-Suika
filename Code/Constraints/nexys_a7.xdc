## ============================================================================
## nexys_a7.xdc
## Vivado constraints for Suika on the Digilent Nexys A7-100T
## (XC7A100T-1CSG324C)
##
## Pin assignments are taken from the official Digilent Nexys A7 master XDC.
## Uncomment / adapt to your variant (Nexys 4 DDR uses identical pinout).
## ============================================================================

## --------- Clock signal (100 MHz) ---------
set_property -dict { PACKAGE_PIN E3   IOSTANDARD LVCMOS33 } [get_ports clk_100]
create_clock -name sysclk -period 10.00 [get_ports clk_100]

## --------- Buttons (active high) ---------
##  btn[0] = BTND (reset)
##  btn[1] = BTNU (drop)
##  btn[2] = BTNL (move left)
##  btn[3] = BTNR (move right)
set_property -dict { PACKAGE_PIN P18  IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN M18  IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
set_property -dict { PACKAGE_PIN P17  IOSTANDARD LVCMOS33 } [get_ports {btn[2]}]
set_property -dict { PACKAGE_PIN M17  IOSTANDARD LVCMOS33 } [get_ports {btn[3]}]

## --------- Switch SW0 (master enable) ---------
set_property -dict { PACKAGE_PIN J15  IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]

## --------- VGA Connector (12-bit, 4-bit per channel) ---------
set_property -dict { PACKAGE_PIN A3   IOSTANDARD LVCMOS33 } [get_ports {vga_r[0]}]
set_property -dict { PACKAGE_PIN B4   IOSTANDARD LVCMOS33 } [get_ports {vga_r[1]}]
set_property -dict { PACKAGE_PIN C5   IOSTANDARD LVCMOS33 } [get_ports {vga_r[2]}]
set_property -dict { PACKAGE_PIN A4   IOSTANDARD LVCMOS33 } [get_ports {vga_r[3]}]

set_property -dict { PACKAGE_PIN C6   IOSTANDARD LVCMOS33 } [get_ports {vga_g[0]}]
set_property -dict { PACKAGE_PIN A5   IOSTANDARD LVCMOS33 } [get_ports {vga_g[1]}]
set_property -dict { PACKAGE_PIN B6   IOSTANDARD LVCMOS33 } [get_ports {vga_g[2]}]
set_property -dict { PACKAGE_PIN A6   IOSTANDARD LVCMOS33 } [get_ports {vga_g[3]}]

set_property -dict { PACKAGE_PIN B7   IOSTANDARD LVCMOS33 } [get_ports {vga_b[0]}]
set_property -dict { PACKAGE_PIN C7   IOSTANDARD LVCMOS33 } [get_ports {vga_b[1]}]
set_property -dict { PACKAGE_PIN D7   IOSTANDARD LVCMOS33 } [get_ports {vga_b[2]}]
set_property -dict { PACKAGE_PIN D8   IOSTANDARD LVCMOS33 } [get_ports {vga_b[3]}]

set_property -dict { PACKAGE_PIN B11  IOSTANDARD LVCMOS33 } [get_ports vga_hs]
set_property -dict { PACKAGE_PIN B12  IOSTANDARD LVCMOS33 } [get_ports vga_vs]

## --------- 7-Segment Display ---------
set_property -dict { PACKAGE_PIN T10  IOSTANDARD LVCMOS33 } [get_ports {seg[0]}]  ;# CA
set_property -dict { PACKAGE_PIN R10  IOSTANDARD LVCMOS33 } [get_ports {seg[1]}]  ;# CB
set_property -dict { PACKAGE_PIN K16  IOSTANDARD LVCMOS33 } [get_ports {seg[2]}]  ;# CC
set_property -dict { PACKAGE_PIN K13  IOSTANDARD LVCMOS33 } [get_ports {seg[3]}]  ;# CD
set_property -dict { PACKAGE_PIN P15  IOSTANDARD LVCMOS33 } [get_ports {seg[4]}]  ;# CE
set_property -dict { PACKAGE_PIN T11  IOSTANDARD LVCMOS33 } [get_ports {seg[5]}]  ;# CF
set_property -dict { PACKAGE_PIN L18  IOSTANDARD LVCMOS33 } [get_ports {seg[6]}]  ;# CG
set_property -dict { PACKAGE_PIN H15  IOSTANDARD LVCMOS33 } [get_ports dp]        ;# DP

set_property -dict { PACKAGE_PIN J17  IOSTANDARD LVCMOS33 } [get_ports {an[0]}]
set_property -dict { PACKAGE_PIN J18  IOSTANDARD LVCMOS33 } [get_ports {an[1]}]
set_property -dict { PACKAGE_PIN T9   IOSTANDARD LVCMOS33 } [get_ports {an[2]}]
set_property -dict { PACKAGE_PIN J14  IOSTANDARD LVCMOS33 } [get_ports {an[3]}]
set_property -dict { PACKAGE_PIN P14  IOSTANDARD LVCMOS33 } [get_ports {an[4]}]
set_property -dict { PACKAGE_PIN T14  IOSTANDARD LVCMOS33 } [get_ports {an[5]}]
set_property -dict { PACKAGE_PIN K2   IOSTANDARD LVCMOS33 } [get_ports {an[6]}]
set_property -dict { PACKAGE_PIN U13  IOSTANDARD LVCMOS33 } [get_ports {an[7]}]

## --------- LEDs ---------
set_property -dict { PACKAGE_PIN H17  IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN K15  IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN J13  IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN N14  IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN R18  IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN V17  IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U17  IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN U16  IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN V16  IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN T15  IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN U14  IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN T16  IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN V15  IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN V14  IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
set_property -dict { PACKAGE_PIN V12  IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
set_property -dict { PACKAGE_PIN V11  IOSTANDARD LVCMOS33 } [get_ports {led[15]}]

## --------- Configuration / bitstream options ---------
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
