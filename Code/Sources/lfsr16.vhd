--==============================================================================
-- lfsr16.vhd
-- 16-bit Galois LFSR. Free-running. Used to pick the next fruit type.
-- Polynomial: x^16 + x^14 + x^13 + x^11 + 1 (taps 16,14,13,11) -- maximal length
--
-- next_type output is in 0..DROP_TYPES-1 (inclusive), produced via mod
-- using a small LUT (DROP_TYPES = 5 by default).
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.suika_pkg.all;

entity lfsr16 is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        next_type  : out unsigned(3 downto 0)   -- 0..DROP_TYPES-1
    );
end entity;

architecture rtl of lfsr16 is
    signal state : std_logic_vector(15 downto 0) := x"ACE1";  -- nonzero seed
begin

    -- Galois LFSR: shift right, XOR feedback into selected taps when LSB=1
    process(clk)
        variable lsb : std_logic;
        variable nxt : std_logic_vector(15 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= x"ACE1";
            else
                lsb := state(0);
                nxt := '0' & state(15 downto 1);     -- shift right
                if lsb = '1' then
                    nxt(15) := '1';                  -- feedback in
                    nxt(13) := nxt(13) xor '1';
                    nxt(12) := nxt(12) xor '1';
                    nxt(10) := nxt(10) xor '1';
                end if;
                state <= nxt;
            end if;
        end if;
    end process;

    -- Reduce to 0..DROP_TYPES-1 with a small LUT on the bottom 3 bits
    process(state)
        variable b : unsigned(2 downto 0);
    begin
        b := unsigned(state(2 downto 0));            -- 0..7
        if b >= to_unsigned(DROP_TYPES, 3) then
            next_type <= resize(b - to_unsigned(DROP_TYPES, 3), 4);
        else
            next_type <= resize(b, 4);
        end if;
    end process;

end architecture;
