-- ============================================================================
-- UART Transmitter Module
-- Mengirim data serial 8N1 pada baud rate 9600
-- Clock: 50 MHz
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx is
    generic (
        CLK_FREQ    : integer := 50000000;  -- 50 MHz
        BAUD_RATE   : integer := 9600       -- 9600 bps
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        data_in     : in  std_logic_vector(7 downto 0);  -- Parallel input
        tx_start    : in  std_logic;        -- Start transmission
        tx          : out std_logic;        -- Serial output
        tx_busy     : out std_logic;        -- Transmitter busy
        tx_done     : out std_logic         -- Transmission complete
    );
end entity uart_tx;

architecture rtl of uart_tx is

    -- Konstanta
    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE;  -- 5208
    
    -- State machine
    type tx_state_type is (IDLE, START_BIT, DATA_BITS, STOP_BIT, CLEANUP);
    signal tx_state : tx_state_type := IDLE;
    
    -- Registers
    signal clk_count    : integer range 0 to CLKS_PER_BIT - 1 := 0;
    signal bit_index    : integer range 0 to 7 := 0;
    signal tx_data      : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_reg       : std_logic := '1';
    signal tx_done_reg  : std_logic := '0';

begin

    -- Main UART TX FSM
    process(clk, rst)
    begin
        if rst = '1' then
            tx_state <= IDLE;
            clk_count <= 0;
            bit_index <= 0;
            tx_data <= (others => '0');
            tx_reg <= '1';  -- Idle high
            tx_done_reg <= '0';
            
        elsif rising_edge(clk) then
            tx_done_reg <= '0';  -- Default
            
            case tx_state is
                when IDLE =>
                    tx_reg <= '1';  -- Idle high
                    clk_count <= 0;
                    bit_index <= 0;
                    
                    if tx_start = '1' then
                        tx_data <= data_in;
                        tx_state <= START_BIT;
                    end if;
                    
                when START_BIT =>
                    tx_reg <= '0';  -- Start bit = 0
                    
                    if clk_count = CLKS_PER_BIT - 1 then
                        clk_count <= 0;
                        tx_state <= DATA_BITS;
                    else
                        clk_count <= clk_count + 1;
                    end if;
                    
                when DATA_BITS =>
                    tx_reg <= tx_data(bit_index);  -- LSB first
                    
                    if clk_count = CLKS_PER_BIT - 1 then
                        clk_count <= 0;
                        
                        if bit_index = 7 then
                            bit_index <= 0;
                            tx_state <= STOP_BIT;
                        else
                            bit_index <= bit_index + 1;
                        end if;
                    else
                        clk_count <= clk_count + 1;
                    end if;
                    
                when STOP_BIT =>
                    tx_reg <= '1';  -- Stop bit = 1
                    
                    if clk_count = CLKS_PER_BIT - 1 then
                        clk_count <= 0;
                        tx_done_reg <= '1';
                        tx_state <= CLEANUP;
                    else
                        clk_count <= clk_count + 1;
                    end if;
                    
                when CLEANUP =>
                    tx_state <= IDLE;
                    
                when others =>
                    tx_state <= IDLE;
            end case;
        end if;
    end process;
    
    -- Output assignments
    tx <= tx_reg;
    tx_done <= tx_done_reg;
    tx_busy <= '0' when tx_state = IDLE else '1';

end architecture rtl;
