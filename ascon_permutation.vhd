-- ============================================================================
-- ASCON Permutation Module (Ascon-p[12])
-- Menjalankan 12 round permutasi secara iteratif (1 round per clock)
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.ascon_pkg.all;

entity ascon_permutation is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        start       : in  std_logic;                      -- Mulai permutasi
        state_in    : in  std_logic_vector(319 downto 0); -- State input 320-bit
        state_out   : out std_logic_vector(319 downto 0); -- State output 320-bit
        done        : out std_logic                       -- Permutasi selesai
    );
end entity ascon_permutation;

architecture rtl of ascon_permutation is

    -- State machine
    type perm_state_type is (IDLE, ROUND_PROCESS, FINISHED);
    signal perm_state : perm_state_type := IDLE;
    
    -- Round counter (0-11)
    signal round_cnt : unsigned(3 downto 0) := (others => '0');
    
    -- Internal state register
    signal state_reg : state_array;
    signal state_next : state_array;
    
    -- Intermediate signals untuk pipeline
    signal after_const : state_array;
    signal after_sbox  : state_array;
    signal after_linear : state_array;

begin

    -- Konversi state_in ke state_array
    -- state_in(319 downto 256) = s0, dst.
    
    -- Proses round: Constant Addition -> S-box -> Linear
    process(state_reg, round_cnt)
        variable temp : state_array;
    begin
        temp := state_reg;
        
        -- Constant Addition Layer (hanya pada word ke-2)
        temp(2) := temp(2) xor (x"00000000000000" & ROUND_CONSTANTS(to_integer(round_cnt)));
        after_const <= temp;
        
        -- Substitution Layer (S-box)
        after_sbox <= sbox_layer(temp);
        
        -- Linear Diffusion Layer
        after_linear <= linear_layer(sbox_layer(temp));
    end process;
    
    -- Main FSM
    process(clk, rst)
    begin
        if rst = '1' then
            perm_state <= IDLE;
            round_cnt <= (others => '0');
            done <= '0';
            for i in 0 to 4 loop
                state_reg(i) <= (others => '0');
            end loop;
            
        elsif rising_edge(clk) then
            case perm_state is
                when IDLE =>
                    done <= '0';
                    if start = '1' then
                        -- Load state dari input
                        state_reg(0) <= state_in(319 downto 256);
                        state_reg(1) <= state_in(255 downto 192);
                        state_reg(2) <= state_in(191 downto 128);
                        state_reg(3) <= state_in(127 downto 64);
                        state_reg(4) <= state_in(63 downto 0);
                        round_cnt <= (others => '0');
                        perm_state <= ROUND_PROCESS;
                    end if;
                    
                when ROUND_PROCESS =>
                    -- Update state dengan hasil round
                    state_reg <= after_linear;
                    
                    if round_cnt = 11 then
                        perm_state <= FINISHED;
                    else
                        round_cnt <= round_cnt + 1;
                    end if;
                    
                when FINISHED =>
                    done <= '1';
                    perm_state <= IDLE;
                    
                when others =>
                    perm_state <= IDLE;
            end case;
        end if;
    end process;
    
    -- Output state
    state_out <= state_reg(0) & state_reg(1) & state_reg(2) & state_reg(3) & state_reg(4);

end architecture rtl;
