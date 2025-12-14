-- ============================================================================
-- ASCON-XOF128 Top Level Entity
-- Target: Cyclone IV EP4CE6E22C8
-- Interface: UART 9600 baud
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.ascon_pkg.all;

entity ascon_xof128_top is
    generic (
        CLK_FREQ    : integer := 50000000;  -- 50 MHz
        BAUD_RATE   : integer := 9600       -- 9600 bps
    );
    port (
        -- Clock and Reset
        clk         : in  std_logic;        -- PIN_24 (50 MHz)
        rst_n       : in  std_logic;        -- PIN_89 (active low)
        
        -- Control Buttons
        btn_start   : in  std_logic;        -- PIN_88 (active low)
        
        -- UART Interface
        uart_rx     : in  std_logic;        -- PIN_87
        uart_tx     : out std_logic;        -- PIN_86
        
        -- Status LEDs
        led         : out std_logic_vector(3 downto 0)  -- PIN_1, 2, 3, 144
    );
end entity ascon_xof128_top;

architecture rtl of ascon_xof128_top is

    -- Internal reset (active high)
    signal rst : std_logic;
    
    -- Debounced start button
    signal start_debounced : std_logic;
    signal start_pulse : std_logic;
    
    -- UART RX signals
    signal rx_data : std_logic_vector(7 downto 0);
    signal rx_valid : std_logic;
    
    -- UART TX signals
    signal tx_data : std_logic_vector(7 downto 0);
    signal tx_start : std_logic;
    signal tx_busy : std_logic;
    signal tx_done : std_logic;
    
    -- Parser signals
    signal msg_data : std_logic_vector(511 downto 0);
    signal msg_len_bytes : unsigned(6 downto 0);
    signal output_len : unsigned(15 downto 0);
    signal parse_done : std_logic;
    signal parse_error : std_logic;
    
    -- Permutation signals
    signal perm_start : std_logic;
    signal perm_state_in : std_logic_vector(319 downto 0);
    signal perm_state_out : std_logic_vector(319 downto 0);
    signal perm_done : std_logic;
    
    -- Hex Converter signals
    signal hash_blk : std_logic_vector(63 downto 0);
    signal hash_valid : std_logic;
    signal ascii_out : std_logic_vector(7 downto 0);
    signal ascii_valid : std_logic;
    signal conv_blk_done : std_logic;
    
    -- Controller signals
    signal led_status : std_logic_vector(3 downto 0);
    signal system_done : std_logic;
    
    -- TX Controller
    signal tx_ready : std_logic;

    -- Debounce counter
    signal debounce_cnt : unsigned(19 downto 0) := (others => '0');
    signal btn_start_sync : std_logic_vector(2 downto 0) := (others => '1');
    signal start_reg : std_logic := '0';

begin

    -- Reset inversion (button is active low)
    rst <= not rst_n;
    
    -- Button debouncing and edge detection
    process(clk, rst)
    begin
        if rst = '1' then
            btn_start_sync <= (others => '1');
            debounce_cnt <= (others => '0');
            start_debounced <= '0';
            start_reg <= '0';
            start_pulse <= '0';
        elsif rising_edge(clk) then
            -- Synchronize button input
            btn_start_sync <= btn_start_sync(1 downto 0) & btn_start;
            
            -- Debounce (20-bit counter ~ 21ms at 50MHz)
            if btn_start_sync(2) /= btn_start_sync(1) then
                debounce_cnt <= (others => '0');
            elsif debounce_cnt < x"FFFFF" then
                debounce_cnt <= debounce_cnt + 1;
            else
                start_debounced <= not btn_start_sync(2);  -- Active low button
            end if;
            
            -- Edge detection for start pulse
            start_reg <= start_debounced;
            start_pulse <= start_debounced and not start_reg;
        end if;
    end process;
    
    -- UART Receiver Instance
    uart_rx_inst : entity work.uart_rx
        generic map (
            CLK_FREQ => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            clk => clk,
            rst => rst,
            rx => uart_rx,
            data_out => rx_data,
            data_valid => rx_valid
        );
    
    -- UART Transmitter Instance
    uart_tx_inst : entity work.uart_tx
        generic map (
            CLK_FREQ => CLK_FREQ,
            BAUD_RATE => BAUD_RATE
        )
        port map (
            clk => clk,
            rst => rst,
            data_in => tx_data,
            tx_start => tx_start,
            tx => uart_tx,
            tx_busy => tx_busy,
            tx_done => tx_done
        );
    
    -- Input Parser Instance
    parser_inst : entity work.input_parser
        port map (
            clk => clk,
            rst => rst,
            rx_data => rx_data,
            rx_valid => rx_valid,
            msg_data => msg_data,
            msg_len_bytes => msg_len_bytes,
            output_len => output_len,
            parse_done => parse_done,
            parse_error => parse_error
        );
    
    -- ASCON Permutation Instance
    perm_inst : entity work.ascon_permutation
        port map (
            clk => clk,
            rst => rst,
            start => perm_start,
            state_in => perm_state_in,
            state_out => perm_state_out,
            done => perm_done
        );
    
    -- Hex Converter Instance
    hex_conv_inst : entity work.hex_converter
        port map (
            clk => clk,
            rst => rst,
            hash_block => hash_blk,
            hash_valid => hash_valid,
            ascii_out => ascii_out,
            ascii_valid => ascii_valid,
            ascii_ready => tx_ready,
            block_done => conv_blk_done
        );
    
    -- Main Controller Instance
    controller_inst : entity work.ascon_controller
        port map (
            clk => clk,
            rst => rst,
            start => start_pulse,
            msg_data => msg_data,
            msg_len_bytes => msg_len_bytes,
            output_len => output_len,
            parse_done => parse_done,
            perm_start => perm_start,
            perm_state_in => perm_state_in,
            perm_state_out => perm_state_out,
            perm_done => perm_done,
            hash_block => hash_blk,
            hash_valid => hash_valid,
            conv_block_done => conv_blk_done,
            led_status => led_status,
            system_done => system_done
        );
    
    -- TX Controller: menghubungkan Hex Converter ke UART TX
    process(clk, rst)
        type tx_ctrl_state is (TX_IDLE, TX_SEND, TX_WAIT);
        variable state : tx_ctrl_state := TX_IDLE;
    begin
        if rst = '1' then
            state := TX_IDLE;
            tx_data <= (others => '0');
            tx_start <= '0';
            tx_ready <= '0';
        elsif rising_edge(clk) then
            tx_start <= '0';
            tx_ready <= '0';
            
            case state is
                when TX_IDLE =>
                    if ascii_valid = '1' then
                        tx_data <= ascii_out;
                        tx_start <= '1';
                        state := TX_SEND;
                    end if;
                    
                when TX_SEND =>
                    state := TX_WAIT;
                    
                when TX_WAIT =>
                    if tx_done = '1' then
                        tx_ready <= '1';
                        state := TX_IDLE;
                    end if;
                    
                when others =>
                    state := TX_IDLE;
            end case;
        end if;
    end process;
    
    -- LED Output
    led <= led_status;

end architecture rtl;
