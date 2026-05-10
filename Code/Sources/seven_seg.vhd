--==============================================================================
-- seven_seg.vhd
-- Drives the Nexys A7's 8-digit 7-segment display.
-- Converts a 16-bit unsigned score (0..65535) to 5 BCD digits using the
-- combinational double-dabble algorithm, then multiplexes them onto
-- 5 of the 8 digits at ~1 kHz.
--
-- All signals are active-LOW (common anode display).
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity seven_seg is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        value   : in  unsigned(15 downto 0);
        seg     : out std_logic_vector(6 downto 0);  -- a..g, active low
        dp      : out std_logic;                     -- decimal point, active low
        an      : out std_logic_vector(7 downto 0)   -- anodes, active low
    );
end entity;

architecture rtl of seven_seg is

    -- Refresh divider: 100 MHz / 2^17 ~= 763 Hz per digit, ~95 Hz total
    signal mux_cnt : unsigned(19 downto 0) := (others => '0');
    signal digit_sel : unsigned(2 downto 0);

    -- BCD storage (5 digits, 4 bits each = 20 bits)
    signal bcd : unsigned(19 downto 0);

    function digit_to_seg(d : unsigned(3 downto 0))
        return std_logic_vector is
    begin
        case d is
            when "0000" => return "1000000";  -- 0
            when "0001" => return "1111001";  -- 1
            when "0010" => return "0100100";  -- 2
            when "0011" => return "0110000";  -- 3
            when "0100" => return "0011001";  -- 4
            when "0101" => return "0010010";  -- 5
            when "0110" => return "0000010";  -- 6
            when "0111" => return "1111000";  -- 7
            when "1000" => return "0000000";  -- 8
            when "1001" => return "0010000";  -- 9
            when others => return "1111111";  -- blank
        end case;
    end function;

begin

    --==========================================================================
    -- Combinational double-dabble: 16-bit binary -> 5 BCD digits
    --==========================================================================
    process(value)
        variable shift : unsigned(35 downto 0);
    begin
        shift := (others => '0');
        shift(15 downto 0) := value;

        for i in 0 to 15 loop
            -- Add 3 to any BCD digit >= 5
            for d in 0 to 4 loop
                if shift(16 + d*4 + 3 downto 16 + d*4) >= 5 then
                    shift(16 + d*4 + 3 downto 16 + d*4)
                        := shift(16 + d*4 + 3 downto 16 + d*4) + 3;
                end if;
            end loop;
            -- Shift left by 1
            shift := shift(34 downto 0) & '0';
        end loop;

        bcd <= shift(35 downto 16);
    end process;

    --==========================================================================
    -- Refresh counter and digit select
    --==========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                mux_cnt <= (others => '0');
            else
                mux_cnt <= mux_cnt + 1;
            end if;
        end if;
    end process;

    digit_sel <= mux_cnt(19 downto 17);

    --==========================================================================
    -- Anode select + segment lookup
    --==========================================================================
    process(digit_sel, bcd)
        variable d : unsigned(3 downto 0);
    begin
        an <= (others => '1');  -- all off
        case digit_sel is
            when "000" =>
                d := bcd(3 downto 0);    an(0) <= '0';
            when "001" =>
                d := bcd(7 downto 4);    an(1) <= '0';
            when "010" =>
                d := bcd(11 downto 8);   an(2) <= '0';
            when "011" =>
                d := bcd(15 downto 12);  an(3) <= '0';
            when "100" =>
                d := bcd(19 downto 16);  an(4) <= '0';
            when others =>
                d := "1111";  -- blank
        end case;
        seg <= digit_to_seg(d);
    end process;

    dp <= '1';  -- decimal point off

end architecture;
