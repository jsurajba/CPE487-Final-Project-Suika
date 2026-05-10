--==============================================================================
-- tb_suika.vhd
-- Testbench for the physics engine.
-- Drives clk + frame_tick directly (no MMCM/VGA needed), simulates several
-- "drop" events, and lets physics run for a few hundred frames so you can
-- observe falling, wall bouncing, collision, and merge behavior in waveforms.
--
-- Recommended waveform signals to add:
--   fruits(0).active, fruits(0).x, fruits(0).y, fruits(0).vy, fruits(0).ftype
--   fruits(1).*, fruits(2).* ...
--   state, score_pulse, score_value, gameover
--==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.suika_pkg.all;

entity tb_suika is
end entity;

architecture sim of tb_suika is
    constant CLK_PERIOD   : time := 25 ns;   -- 40 MHz
    constant FRAME_PERIOD : time := 16.67 ms; -- 60 Hz

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal frame_tick  : std_logic := '0';
    signal spawn_req   : std_logic := '0';
    signal spawn_x     : unsigned(10 downto 0) := to_unsigned(400, 11);
    signal spawn_type  : unsigned(3 downto 0)  := (others => '0');
    signal fruits      : fruit_array_t;
    signal busy        : std_logic;
    signal gameover    : std_logic;
    signal score_pulse : std_logic;
    signal score_value : unsigned(7 downto 0);

    signal sim_done : boolean := false;
begin

    --==========================================================================
    -- Clock
    --==========================================================================
    clk_proc : process
    begin
        while not sim_done loop
            clk <= '0'; wait for CLK_PERIOD/2;
            clk <= '1'; wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    --==========================================================================
    -- Frame ticks: 1 cycle wide, every FRAME_PERIOD
    --==========================================================================
    frame_proc : process
    begin
        while not sim_done loop
            wait for FRAME_PERIOD;
            wait until rising_edge(clk);
            frame_tick <= '1';
            wait until rising_edge(clk);
            frame_tick <= '0';
        end loop;
        wait;
    end process;

    --==========================================================================
    -- DUT
    --==========================================================================
    dut : entity work.physics_engine
        port map (
            clk         => clk,
            rst         => rst,
            frame_tick  => frame_tick,
            spawn_req   => spawn_req,
            spawn_x     => spawn_x,
            spawn_type  => spawn_type,
            fruits_out  => fruits,
            busy        => busy,
            gameover    => gameover,
            score_pulse => score_pulse,
            score_value => score_value
        );

    --==========================================================================
    -- Stimulus
    --==========================================================================
    stim : process
        procedure drop(x : integer; t : integer) is
        begin
            wait until rising_edge(clk);
            spawn_x    <= to_unsigned(x, 11);
            spawn_type <= to_unsigned(t, 4);
            spawn_req  <= '1';
            wait until rising_edge(clk);
            spawn_req  <= '0';
        end procedure;
    begin
        -- Reset
        rst <= '1';
        wait for 200 ns;
        rst <= '0';
        wait for 1 us;

        -- Drop 1: cherry (type 0) near center
        drop(400, 0);
        wait for FRAME_PERIOD * 30;

        -- Drop 2: cherry next to it -- should merge into strawberry (type 1)
        drop(420, 0);
        wait for FRAME_PERIOD * 60;

        -- Drop 3: another cherry -- to test 3-fruit pile
        drop(380, 0);
        wait for FRAME_PERIOD * 40;

        -- Drop 4-6: stack some bigger ones
        drop(350, 1);  wait for FRAME_PERIOD * 30;
        drop(450, 1);  wait for FRAME_PERIOD * 30;
        drop(400, 2);  wait for FRAME_PERIOD * 30;

        -- Test wall collision: drop near edge with offset
        drop(260, 0);  wait for FRAME_PERIOD * 30;
        drop(540, 0);  wait for FRAME_PERIOD * 60;

        -- Many rapid drops to stress collision system
        for i in 0 to 9 loop
            drop(300 + i*25, i mod 3);
            wait for FRAME_PERIOD * 5;
        end loop;
        wait for FRAME_PERIOD * 100;

        report "Simulation complete" severity note;
        sim_done <= true;
        wait;
    end process;

end architecture;
