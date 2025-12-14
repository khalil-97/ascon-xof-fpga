-- ============================================================================
-- UART Receiver Module
-- Menerima data serial 8N1 pada baud rate 9600
-- Clock: 50 MHz
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_rx is
    generic (
        CLK_FREQ    : integer := 50000000;  -- 50 MHz
        BAUD_RATE   : integer := 9600       -- 9600 bps
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        rx          : in  std_logic;        -- Serial input
        data_out    : out std_logic_vector(7 downto 0);  -- Parallel output
        data_valid  : out std_logic         -- Data valid pulse
    );
end entity uart_rx;

architecture rtl of uart_rx is

    -- Konstanta
    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE;  -- 5208 untuk 50MHz/9600
    
    -- State machine
    type rx_state_type is (IDLE, START_BIT, DATA_BITS, STOP_BIT, CLEANUP);
    signal rx_state : rx_state_type := IDLE;
    
    -- Registers
    signal clk_count    : integer range 0 to CLKS_PER_BIT - 1 := 0;
    signal bit_index    : integer range 0 to 7 := 0;
    signal rx_data      : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_done      : std_logic := '0';
    
    -- Double register untuk sinkronisasi
    signal rx_sync1     : std_logic := '1';
    signal rx_sync2     : std_logic := '1';

begin

    -- Sinkronisasi input RX (metastability prevention)
    process(clk, rst)
    begin
        if rst = '1' then
            rx_sync1 <= '1';
            rx_sync2 <= '1';
        elsif rising_edge(clk) then
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end if;
    end process;

    -- Main UART RX FSM
    process(clk, rst)
    begin
        if rst = '1' then
            rx_state <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            rx_data <= (others => '0');
            rx_done <= '0';
            
        elsif rising_edge(clk) then
            rx_done <= '0';  -- Default: no valid data
            
            case rx_state is
                when IDLE =>
                    clk_count <= 0;
                    bit_index <= 0;
                    
                    -- Deteksi start bit (falling edge, RX goes low)
                    if rx_sync2 = '0' then
                        rx_state <= START_BIT;
                    end if;
                    
                when START_BIT =>
                    -- Sample di tengah start bit
                    if clk_count = (CLKS_PER_BIT - 1) / 2 then
                        if rx_sync2 = '0' then
                            -- Valid start bit
                            clk_count <= 0;
                            rx_state <= DATA_BITS;
                        else
                            -- False start, kembali ke IDLE
                            rx_state <= IDLE;
                        end if;
                    else
                        clk_count <= clk_count + 1;
                    end if;
                    
                when DATA_BITS =>
                    -- Sample di tengah setiap data bit
                    if clk_count = CLKS_PER_BIT - 1 then
                        clk_count <= 0;
                        rx_data(bit_index) <= rx_sync2;  -- LSB first
                        
                        if bit_index = 7 then
                            bit_index <= 0;
                            rx_state <= STOP_BIT;
                        else
                            bit_index <= bit_index + 1;
                        end if;
                    else
                        clk_count <= clk_count + 1;
                    end if;
                    
                when STOP_BIT =>
                    -- Tunggu sampai tengah stop bit
                    if clk_count = CLKS_PER_BIT - 1 then
                        clk_count <= 0;
                        rx_done <= '1';  -- Data valid
                        rx_state <= CLEANUP;
                    else
                        clk_count <= clk_count + 1;
                    end if;
                    
                when CLEANUP =>
                    -- Satu clock untuk cleanup
                    rx_state <= IDLE;
                    
                when others =>
                    rx_state <= IDLE;
            end case;
        end if;
    end process;
    
    -- Output assignments
    data_out <= rx_data;
    data_valid <= rx_done;

end architecture rtl;
