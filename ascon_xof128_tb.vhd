-- ============================================================================
-- Testbench for ASCON-XOF128 Top Level
-- Simulasi pengiriman "Hi#128" dan menerima output hash
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ascon_xof128_tb is
end entity ascon_xof128_tb;

architecture sim of ascon_xof128_tb is

    -- Clock period
    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz
    constant BIT_PERIOD : time := 104167 ns;  -- 9600 baud
    
    -- Signals
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal btn_start : std_logic := '1';  -- Active low, idle high
    signal uart_rx : std_logic := '1';  -- Idle high
    signal uart_tx : std_logic;
    signal led : std_logic_vector(3 downto 0);
    
    -- Test message: "Hi#128" + CR
    type byte_array is array (natural range <>) of std_logic_vector(7 downto 0);
    constant TEST_MSG : byte_array := (
        x"48",  -- 'H'
        x"69",  -- 'i'
        x"23",  -- '#'
        x"31",  -- '1'
        x"32",  -- '2'
        x"38",  -- '8'
        x"0D"   -- CR (Enter)
    );
    
    -- Procedure untuk mengirim satu byte via UART
    procedure uart_send_byte(
        signal tx_line : out std_logic;
        data : std_logic_vector(7 downto 0)
    ) is
    begin
        -- Start bit
        tx_line <= '0';
        wait for BIT_PERIOD;
        
        -- Data bits (LSB first)
        for i in 0 to 7 loop
            tx_line <= data(i);
            wait for BIT_PERIOD;
        end loop;
        
        -- Stop bit
        tx_line <= '1';
        wait for BIT_PERIOD;
    end procedure;

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD / 2;
    
    -- DUT instantiation
    dut : entity work.ascon_xof128_top
        generic map (
            CLK_FREQ => 50000000,
            BAUD_RATE => 9600
        )
        port map (
            clk => clk,
            rst_n => rst_n,
            btn_start => btn_start,
            uart_rx => uart_rx,
            uart_tx => uart_tx,
            led => led
        );
    
    -- Stimulus process
    stim_proc : process
    begin
        -- Initial reset
        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait for 100 ns;
        
        -- Tunggu sistem stabil
        wait for 1 ms;
        
        -- Kirim test message via UART
        report "Sending test message: Hi#128";
        for i in TEST_MSG'range loop
            uart_send_byte(uart_rx, TEST_MSG(i));
            wait for BIT_PERIOD;  -- Gap antar byte
        end loop;
        
        -- Tunggu parsing selesai
        wait for 1 ms;
        
        -- Tekan tombol start
        report "Pressing START button";
        btn_start <= '0';  -- Active low
        wait for 50 ms;    -- Debounce time
        btn_start <= '1';
        
        -- Tunggu proses selesai
        wait until led = "1111";
        report "Hash computation complete!";
        
        -- Tunggu output UART selesai
        wait for 100 ms;
        
        report "Simulation complete";
        wait;
    end process;
    
    -- Monitor LED status
    led_monitor : process(led)
    begin
        case led is
            when "0001" => report "Status: IDLE";
            when "0010" => report "Status: INITIALIZATION";
            when "0100" => report "Status: ABSORBING";
            when "1000" => report "Status: SQUEEZING";
            when "1111" => report "Status: DONE";
            when others => null;
        end case;
    end process;
    
    -- Monitor UART TX output
    uart_monitor : process
        variable rx_byte : std_logic_vector(7 downto 0);
        variable char : character;
    begin
        wait until uart_tx = '0';  -- Wait for start bit
        wait for BIT_PERIOD / 2;   -- Go to middle of start bit
        wait for BIT_PERIOD;       -- Skip start bit
        
        -- Read 8 data bits
        for i in 0 to 7 loop
            rx_byte(i) := uart_tx;
            wait for BIT_PERIOD;
        end loop;
        
        -- Convert to character and report
        char := character'val(to_integer(unsigned(rx_byte)));
        report "UART TX: " & char;
    end process;

end architecture sim;
