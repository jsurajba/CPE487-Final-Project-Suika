--==============================================================================
-- debouncer.vhd
-- Button debouncer with edge detection.
-- Inputs are sampled, debounced over ~10 ms, and a one-cycle "pressed" pulse
-- is emitted on the rising (press) edge.
--
-- At 100 MHz, 10 ms = 1,000,000 cycles. We use a 20-bit counter (2^20 = ~10ms).
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debouncer is
    generic (
        CLK_HZ      : integer := 100_000_000;
        DEBOUNCE_MS : integer := 10
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        btn_in    : in  std_logic;   -- raw button (active high)
        btn_level : out std_logic;   -- debounced level (held)
        btn_press : out std_logic    -- 1-cycle pulse on rising edge
    );
end entity;

architecture rtl of debouncer is
    constant MAX_CNT : integer := (CLK_HZ / 1000) * DEBOUNCE_MS;

    signal sync0, sync1 : std_logic := '0';
    signal counter      : integer range 0 to MAX_CNT := 0;
    signal stable       : std_logic := '0';
    signal stable_d     : std_logic := '0';
begin

    -- Two-stage synchronizer for asynchronous button input
    process(clk)
    begin
        if rising_edge(clk) then
            sync0 <= btn_in;
            sync1 <= sync0;
        end if;
    end process;

    -- Counter holds value steady when input matches; releases when it changes.
    -- When counter saturates, sample is considered stable.
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                counter  <= 0;
                stable   <= '0';
                stable_d <= '0';
            else
                if sync1 /= stable then
                    if counter = MAX_CNT then
                        stable  <= sync1;
                        counter <= 0;
                    else
                        counter <= counter + 1;
                    end if;
                else
                    counter <= 0;
                end if;
                stable_d <= stable;
            end if;
        end if;
    end process;

    btn_level <= stable;
    btn_press <= stable and not stable_d;

end architecture;
