-- ============================================================================
-- Hex Converter Module
-- Mengkonversi 4-bit nibble menjadi karakter ASCII hexadecimal
-- 0-9 -> '0'-'9' (0x30-0x39)
-- A-F -> 'A'-'F' (0x41-0x46)
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity hex_converter is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        
        -- Input: 64-bit hash block
        hash_block  : in  std_logic_vector(63 downto 0);
        hash_valid  : in  std_logic;
        
        -- Output: ASCII byte
        ascii_out   : out std_logic_vector(7 downto 0);
        ascii_valid : out std_logic;
        ascii_ready : in  std_logic;  -- TX ready for next byte
        
        -- Status
        block_done  : out std_logic   -- Seluruh block sudah dikonversi
    );
end entity hex_converter;

architecture rtl of hex_converter is

    -- State machine
    type conv_state_type is (IDLE, CONVERTING, WAIT_TX, NEXT_NIBBLE, DONE);
    signal conv_state : conv_state_type := IDLE;
    
    -- Buffer untuk hash block
    signal hash_buffer : std_logic_vector(63 downto 0) := (others => '0');
    
    -- Nibble counter (0-15, 16 nibbles per 64-bit block)
    signal nibble_cnt : unsigned(4 downto 0) := (others => '0');
    
    -- Current nibble
    signal current_nibble : std_logic_vector(3 downto 0);
    signal ascii_byte : std_logic_vector(7 downto 0);

begin

    -- Ekstrak nibble dari posisi saat ini (MSB first)
    -- nibble 0 = bit 63-60, nibble 1 = bit 59-56, dst.
    current_nibble <= hash_buffer(63 - to_integer(nibble_cnt)*4 downto 60 - to_integer(nibble_cnt)*4);
    
    -- Konversi nibble ke ASCII
    process(current_nibble)
    begin
        case current_nibble is
            when "0000" => ascii_byte <= x"30";  -- '0'
            when "0001" => ascii_byte <= x"31";  -- '1'
            when "0010" => ascii_byte <= x"32";  -- '2'
            when "0011" => ascii_byte <= x"33";  -- '3'
            when "0100" => ascii_byte <= x"34";  -- '4'
            when "0101" => ascii_byte <= x"35";  -- '5'
            when "0110" => ascii_byte <= x"36";  -- '6'
            when "0111" => ascii_byte <= x"37";  -- '7'
            when "1000" => ascii_byte <= x"38";  -- '8'
            when "1001" => ascii_byte <= x"39";  -- '9'
            when "1010" => ascii_byte <= x"41";  -- 'A'
            when "1011" => ascii_byte <= x"42";  -- 'B'
            when "1100" => ascii_byte <= x"43";  -- 'C'
            when "1101" => ascii_byte <= x"44";  -- 'D'
            when "1110" => ascii_byte <= x"45";  -- 'E'
            when "1111" => ascii_byte <= x"46";  -- 'F'
            when others => ascii_byte <= x"3F";  -- '?' (error)
        end case;
    end process;
    
    -- Main FSM
    process(clk, rst)
    begin
        if rst = '1' then
            conv_state <= IDLE;
            hash_buffer <= (others => '0');
            nibble_cnt <= (others => '0');
            ascii_valid <= '0';
            block_done <= '0';
            
        elsif rising_edge(clk) then
            ascii_valid <= '0';
            block_done <= '0';
            
            case conv_state is
                when IDLE =>
                    nibble_cnt <= (others => '0');
                    if hash_valid = '1' then
                        hash_buffer <= hash_block;
                        conv_state <= CONVERTING;
                    end if;
                    
                when CONVERTING =>
                    -- Output ASCII byte
                    ascii_valid <= '1';
                    conv_state <= WAIT_TX;
                    
                when WAIT_TX =>
                    -- Tunggu TX selesai
                    if ascii_ready = '1' then
                        conv_state <= NEXT_NIBBLE;
                    end if;
                    
                when NEXT_NIBBLE =>
                    if nibble_cnt = 15 then
                        -- Semua 16 nibbles sudah dikonversi
                        conv_state <= DONE;
                    else
                        nibble_cnt <= nibble_cnt + 1;
                        conv_state <= CONVERTING;
                    end if;
                    
                when DONE =>
                    block_done <= '1';
                    conv_state <= IDLE;
                    
                when others =>
                    conv_state <= IDLE;
            end case;
        end if;
    end process;
    
    -- Output
    ascii_out <= ascii_byte;

end architecture rtl;
