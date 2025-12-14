-- ============================================================================
-- Input Parser Module
-- Memproses input format: [Message]#[Length]
-- Contoh: "Hello#128" -> Message="Hello", L=128
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity input_parser is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        
        -- Input dari UART RX
        rx_data         : in  std_logic_vector(7 downto 0);
        rx_valid        : in  std_logic;
        
        -- Output Message Buffer (max 64 bytes = 512 bits)
        msg_data        : out std_logic_vector(511 downto 0);
        msg_len_bytes   : out unsigned(6 downto 0);  -- 0-64 bytes
        
        -- Output Length L (dalam bits)
        output_len      : out unsigned(15 downto 0);  -- Max 65535 bits
        
        -- Control signals
        parse_done      : out std_logic;  -- Parsing selesai
        parse_error     : out std_logic   -- Error dalam parsing
    );
end entity input_parser;

architecture rtl of input_parser is

    -- State machine
    type parser_state_type is (IDLE, RECV_MSG, RECV_LEN, DONE, ERROR_STATE);
    signal parser_state : parser_state_type := IDLE;
    
    -- Message buffer (64 bytes max)
    signal msg_buffer : std_logic_vector(511 downto 0) := (others => '0');
    signal msg_byte_cnt : unsigned(6 downto 0) := (others => '0');
    
    -- Length accumulator
    signal len_accum : unsigned(15 downto 0) := (others => '0');
    
    -- ASCII constants
    constant ASCII_HASH : std_logic_vector(7 downto 0) := x"23";  -- '#'
    constant ASCII_0    : std_logic_vector(7 downto 0) := x"30";  -- '0'
    constant ASCII_9    : std_logic_vector(7 downto 0) := x"39";  -- '9'
    constant ASCII_CR   : std_logic_vector(7 downto 0) := x"0D";  -- Carriage Return
    constant ASCII_LF   : std_logic_vector(7 downto 0) := x"0A";  -- Line Feed

begin

    process(clk, rst)
        variable digit_val : unsigned(3 downto 0);
    begin
        if rst = '1' then
            parser_state <= IDLE;
            msg_buffer <= (others => '0');
            msg_byte_cnt <= (others => '0');
            len_accum <= (others => '0');
            parse_done <= '0';
            parse_error <= '0';
            
        elsif rising_edge(clk) then
            parse_done <= '0';
            parse_error <= '0';
            
            case parser_state is
                when IDLE =>
                    msg_buffer <= (others => '0');
                    msg_byte_cnt <= (others => '0');
                    len_accum <= (others => '0');
                    
                    -- Mulai jika ada data valid (bukan whitespace)
                    if rx_valid = '1' then
                        if rx_data /= ASCII_CR and rx_data /= ASCII_LF then
                            if rx_data = ASCII_HASH then
                                -- Langsung ke length (message kosong)
                                parser_state <= RECV_LEN;
                            else
                                -- Simpan byte pertama message
                                msg_buffer(511 downto 504) <= rx_data;
                                msg_byte_cnt <= to_unsigned(1, 7);
                                parser_state <= RECV_MSG;
                            end if;
                        end if;
                    end if;
                    
                when RECV_MSG =>
                    if rx_valid = '1' then
                        if rx_data = ASCII_HASH then
                            -- Delimiter ditemukan, pindah ke parsing length
                            parser_state <= RECV_LEN;
                            
                        elsif rx_data = ASCII_CR or rx_data = ASCII_LF then
                            -- End of line tanpa length = error
                            parser_state <= ERROR_STATE;
                            
                        elsif msg_byte_cnt < 64 then
                            -- Simpan byte ke buffer (shift left)
                            msg_buffer <= msg_buffer(503 downto 0) & rx_data;
                            msg_byte_cnt <= msg_byte_cnt + 1;
                        else
                            -- Buffer penuh = error
                            parser_state <= ERROR_STATE;
                        end if;
                    end if;
                    
                when RECV_LEN =>
                    if rx_valid = '1' then
                        if rx_data = ASCII_CR or rx_data = ASCII_LF then
                            -- End of input, parsing selesai
                            if len_accum > 0 then
                                parser_state <= DONE;
                            else
                                -- Length = 0 tidak valid
                                parser_state <= ERROR_STATE;
                            end if;
                            
                        elsif rx_data >= ASCII_0 and rx_data <= ASCII_9 then
                            -- Konversi ASCII digit ke nilai
                            digit_val := unsigned(rx_data(3 downto 0));
                            -- len_accum = len_accum * 10 + digit
                            len_accum <= resize(len_accum * 10 + digit_val, 16);
                            
                        else
                            -- Karakter non-digit = error
                            parser_state <= ERROR_STATE;
                        end if;
                    end if;
                    
                when DONE =>
                    parse_done <= '1';
                    parser_state <= IDLE;
                    
                when ERROR_STATE =>
                    parse_error <= '1';
                    parser_state <= IDLE;
                    
                when others =>
                    parser_state <= IDLE;
            end case;
        end if;
    end process;
    
    -- Output assignments
    msg_data <= msg_buffer;
    msg_len_bytes <= msg_byte_cnt;
    output_len <= len_accum;

end architecture rtl;
