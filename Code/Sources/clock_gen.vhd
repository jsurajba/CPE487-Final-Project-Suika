--==============================================================================
-- clock_gen.vhd
-- Generates a 40 MHz pixel clock from the Nexys A7's 100 MHz system clock.
-- Uses the Artix-7 MMCME2_BASE primitive directly (no IP wrapper required).
--
-- VCO = 100 MHz * (CLKFBOUT_MULT_F / DIVCLK_DIVIDE) = 100 * 8 / 1 = 800 MHz
-- f_pix = 800 MHz / CLKOUT0_DIVIDE_F = 800 / 20 = 40 MHz
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity clock_gen is
    port (
        clk_100   : in  std_logic;   -- 100 MHz from board
        rst       : in  std_logic;   -- async reset
        clk_pix   : out std_logic;   -- 40 MHz output
        locked    : out std_logic    -- '1' when MMCM is locked
    );
end entity;

architecture rtl of clock_gen is
    signal clkfb     : std_logic;
    signal clkout0_b : std_logic;
    signal clkfb_b   : std_logic;
begin

    mmcm_inst : MMCME2_BASE
        generic map (
            BANDWIDTH        => "OPTIMIZED",
            CLKFBOUT_MULT_F  => 8.000,
            CLKFBOUT_PHASE   => 0.000,
            CLKIN1_PERIOD    => 10.000,    -- 100 MHz period in ns
            CLKOUT0_DIVIDE_F => 20.000,
            CLKOUT0_DUTY_CYCLE => 0.500,
            CLKOUT0_PHASE    => 0.000,
            DIVCLK_DIVIDE    => 1,
            REF_JITTER1      => 0.010,
            STARTUP_WAIT     => FALSE
        )
        port map (
            CLKOUT0  => clkout0_b,
            CLKOUT0B => open,
            CLKOUT1  => open, CLKOUT1B => open,
            CLKOUT2  => open, CLKOUT2B => open,
            CLKOUT3  => open, CLKOUT3B => open,
            CLKOUT4  => open, CLKOUT5  => open, CLKOUT6 => open,
            CLKFBOUT => clkfb_b,
            CLKFBOUTB=> open,
            LOCKED   => locked,
            CLKIN1   => clk_100,
            PWRDWN   => '0',
            RST      => rst,
            CLKFBIN  => clkfb
        );

    -- Buffer the feedback and output clocks
    bufg_fb : BUFG port map (I => clkfb_b,   O => clkfb);
    bufg_p  : BUFG port map (I => clkout0_b, O => clk_pix);

end architecture;
