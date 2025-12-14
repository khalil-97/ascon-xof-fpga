-- ============================================================================
-- ASCON-XOF128 Main FSM Controller
-- Mengontrol alur kerja keseluruhan sistem:
-- IDLE -> INIT -> ABSORB -> SQUEEZE -> OUTPUT -> DONE
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.ascon_pkg.all;

entity ascon_controller is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        start           : in  std_logic;  -- Tombol start
        
        -- Input dari Parser
        msg_data        : in  std_logic_vector(511 downto 0);
        msg_len_bytes   : in  unsigned(6 downto 0);
        output_len      : in  unsigned(15 downto 0);  -- L dalam bits
        parse_done      : in  std_logic;
        
        -- Interface ke Permutation
        perm_start      : out std_logic;
        perm_state_in   : out std_logic_vector(319 downto 0);
        perm_state_out  : in  std_logic_vector(319 downto 0);
        perm_done       : in  std_logic;
        
        -- Interface ke Hex Converter
        hash_block      : out std_logic_vector(63 downto 0);
        hash_valid      : out std_logic;
        conv_block_done : in  std_logic;
        
        -- Status outputs
        led_status      : out std_logic_vector(3 downto 0);
        system_done     : out std_logic
    );
end entity ascon_controller;

architecture rtl of ascon_controller is

    -- Main FSM States
    type main_state_type is (
        S_IDLE,
        S_LOAD_IV,
        S_PERM_INIT,
        S_WAIT_PERM_INIT,
        S_ABSORB_XOR,
        S_PERM_ABSORB,
        S_WAIT_PERM_ABS,
        S_ABSORB_NEXT,
        S_PERM_SQUEEZE,
        S_WAIT_PERM_SQ,
        S_EXTRACT,
        S_WAIT_OUTPUT,
        S_SQUEEZE_NEXT,
        S_DONE
    );
    signal main_state : main_state_type := S_IDLE;
    
    -- State Register (320-bit)
    signal state_reg : std_logic_vector(319 downto 0) := (others => '0');
    
    -- Counters
    signal absorb_blk_cnt : unsigned(3 downto 0) := (others => '0');  -- Max 8 blocks (512 bits / 64)
    signal squeeze_blk_cnt : unsigned(9 downto 0) := (others => '0'); -- Max 1024 blocks
    signal total_absorb_blks : unsigned(3 downto 0);
    signal total_squeeze_blks : unsigned(9 downto 0);
    
    -- Message block selector
    signal current_msg_blk : std_logic_vector(63 downto 0);
    
    -- Padding
    signal padded_blk : std_logic_vector(63 downto 0);
    signal is_last_blk : std_logic;
    
    -- Internal signals
    signal data_ready : std_logic := '0';

begin

    -- Hitung jumlah block untuk absorb dan squeeze
    -- Absorb blocks = ceil(msg_len_bytes / 8)
    total_absorb_blks <= resize(shift_right(msg_len_bytes + 7, 3), 4);
    
    -- Squeeze blocks = ceil(output_len / 64)
    total_squeeze_blks <= resize(shift_right(output_len + 63, 6), 10);
    
    -- Pilih message block berdasarkan counter
    process(msg_data, absorb_blk_cnt, msg_len_bytes)
        variable start_bit : integer;
        variable msg_blk : std_logic_vector(63 downto 0);
        variable remaining_bytes : integer;
        variable byte_offset : integer;
    begin
        start_bit := 511 - to_integer(absorb_blk_cnt) * 64;
        
        if start_bit >= 63 then
            msg_blk := msg_data(start_bit downto start_bit - 63);
        else
            msg_blk := (others => '0');
        end if;
        
        -- Cek apakah ini block terakhir
        byte_offset := to_integer(absorb_blk_cnt) * 8;
        remaining_bytes := to_integer(msg_len_bytes) - byte_offset;
        
        if remaining_bytes <= 8 then
            is_last_blk <= '1';
            -- Apply padding: 1 bit followed by zeros
            -- Padding sesuai NIST: pad(X, r) = X || 1 || 0^j where j = (-|X| - 1) mod r
            if remaining_bytes < 8 then
                -- Perlu padding dalam block ini
                case remaining_bytes is
                    when 0 => padded_blk <= x"8000000000000000";
                    when 1 => padded_blk <= msg_blk(63 downto 56) & x"80" & x"000000000000";
                    when 2 => padded_blk <= msg_blk(63 downto 48) & x"80" & x"0000000000";
                    when 3 => padded_blk <= msg_blk(63 downto 40) & x"80" & x"00000000";
                    when 4 => padded_blk <= msg_blk(63 downto 32) & x"80" & x"000000";
                    when 5 => padded_blk <= msg_blk(63 downto 24) & x"80" & x"0000";
                    when 6 => padded_blk <= msg_blk(63 downto 16) & x"80" & x"00";
                    when 7 => padded_blk <= msg_blk(63 downto 8) & x"80";
                    when others => padded_blk <= msg_blk;
                end case;
            else
                -- Full block, padding di block berikutnya tidak diperlukan untuk XOF
                padded_blk <= msg_blk;
            end if;
        else
            is_last_blk <= '0';
            padded_blk <= msg_blk;
        end if;
        
        current_msg_blk <= msg_blk;
    end process;
    
    -- Main FSM
    process(clk, rst)
    begin
        if rst = '1' then
            main_state <= S_IDLE;
            state_reg <= (others => '0');
            absorb_blk_cnt <= (others => '0');
            squeeze_blk_cnt <= (others => '0');
            perm_start <= '0';
            hash_valid <= '0';
            system_done <= '0';
            data_ready <= '0';
            led_status <= "0001";  -- IDLE
            
        elsif rising_edge(clk) then
            perm_start <= '0';
            hash_valid <= '0';
            system_done <= '0';
            
            case main_state is
                -- ========== IDLE ==========
                when S_IDLE =>
                    led_status <= "0001";
                    absorb_blk_cnt <= (others => '0');
                    squeeze_blk_cnt <= (others => '0');
                    
                    if parse_done = '1' then
                        data_ready <= '1';
                    end if;
                    
                    if start = '1' and data_ready = '1' then
                        main_state <= S_LOAD_IV;
                        data_ready <= '0';
                    end if;
                    
                -- ========== INITIALIZATION ==========
                when S_LOAD_IV =>
                    led_status <= "0010";
                    -- Load IV || 0^256
                    state_reg <= IV_XOF128 & x"0000000000000000" & 
                                 x"0000000000000000" & x"0000000000000000" & 
                                 x"0000000000000000";
                    main_state <= S_PERM_INIT;
                    
                when S_PERM_INIT =>
                    perm_start <= '1';
                    main_state <= S_WAIT_PERM_INIT;
                    
                when S_WAIT_PERM_INIT =>
                    if perm_done = '1' then
                        state_reg <= perm_state_out;
                        main_state <= S_ABSORB_XOR;
                    end if;
                    
                -- ========== ABSORBING ==========
                when S_ABSORB_XOR =>
                    led_status <= "0100";
                    -- XOR message block dengan rate (S[0:63])
                    if msg_len_bytes = 0 then
                        -- Empty message, langsung ke squeeze
                        -- XOR dengan padding saja
                        state_reg(319 downto 256) <= state_reg(319 downto 256) xor x"8000000000000000";
                        main_state <= S_PERM_SQUEEZE;
                    else
                        state_reg(319 downto 256) <= state_reg(319 downto 256) xor padded_blk;
                        
                        if is_last_blk = '1' then
                            -- Block terakhir, langsung ke squeeze
                            main_state <= S_PERM_SQUEEZE;
                        else
                            -- Masih ada block lagi
                            main_state <= S_PERM_ABSORB;
                        end if;
                    end if;
                    
                when S_PERM_ABSORB =>
                    perm_start <= '1';
                    main_state <= S_WAIT_PERM_ABS;
                    
                when S_WAIT_PERM_ABS =>
                    if perm_done = '1' then
                        state_reg <= perm_state_out;
                        main_state <= S_ABSORB_NEXT;
                    end if;
                    
                when S_ABSORB_NEXT =>
                    absorb_blk_cnt <= absorb_blk_cnt + 1;
                    main_state <= S_ABSORB_XOR;
                    
                -- ========== SQUEEZING ==========
                when S_PERM_SQUEEZE =>
                    led_status <= "1000";
                    perm_start <= '1';
                    main_state <= S_WAIT_PERM_SQ;
                    
                when S_WAIT_PERM_SQ =>
                    if perm_done = '1' then
                        state_reg <= perm_state_out;
                        main_state <= S_EXTRACT;
                    end if;
                    
                when S_EXTRACT =>
                    -- Kirim rate (64-bit) ke Hex Converter
                    hash_valid <= '1';
                    main_state <= S_WAIT_OUTPUT;
                    
                when S_WAIT_OUTPUT =>
                    if conv_block_done = '1' then
                        main_state <= S_SQUEEZE_NEXT;
                    end if;
                    
                when S_SQUEEZE_NEXT =>
                    squeeze_blk_cnt <= squeeze_blk_cnt + 1;
                    
                    if squeeze_blk_cnt + 1 >= total_squeeze_blks then
                        -- Semua block output sudah diekstrak
                        main_state <= S_DONE;
                    else
                        -- Masih butuh block lagi
                        main_state <= S_PERM_SQUEEZE;
                    end if;
                    
                -- ========== DONE ==========
                when S_DONE =>
                    led_status <= "1111";
                    system_done <= '1';
                    main_state <= S_IDLE;
                    
                when others =>
                    main_state <= S_IDLE;
            end case;
        end if;
    end process;
    
    -- Output assignments
    perm_state_in <= state_reg;
    hash_block <= state_reg(319 downto 256);  -- Rate = S[0:63]

end architecture rtl;
