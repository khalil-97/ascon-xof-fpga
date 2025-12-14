-- ============================================================================
-- ASCON-XOF128 Package
-- Berisi konstanta, tipe data, dan fungsi untuk ASCON-XOF128
-- Sesuai dengan NIST SP 800-232
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package ascon_pkg is

    -- Konstanta ASCON-XOF128 sesuai NIST SP 800-232
    constant IV_XOF128 : std_logic_vector(63 downto 0) := x"0000080000cc0003";
    
    -- Konstanta untuk permutasi (round constants)
    type round_const_array is array (0 to 11) of std_logic_vector(7 downto 0);
    constant ROUND_CONSTANTS : round_const_array := (
        x"3c", x"2d", x"1e", x"0f",
        x"f0", x"e1", x"d2", x"c3",
        x"b4", x"a5", x"96", x"87"
    );
    
    -- Tipe data untuk state 320-bit (5 x 64-bit words)
    type state_array is array (0 to 4) of std_logic_vector(63 downto 0);
    
    -- Fungsi rotasi kanan untuk 64-bit
    function rotate_right(x : std_logic_vector(63 downto 0); n : integer) return std_logic_vector;
    
    -- Fungsi S-box layer
    function sbox_layer(s : state_array) return state_array;
    
    -- Fungsi Linear diffusion layer
    function linear_layer(s : state_array) return state_array;

end package ascon_pkg;

package body ascon_pkg is

    -- Implementasi fungsi rotasi kanan
    function rotate_right(x : std_logic_vector(63 downto 0); n : integer) return std_logic_vector is
    begin
        return x(n-1 downto 0) & x(63 downto n);
    end function;
    
    -- Implementasi S-box layer (5-bit S-box diterapkan 64 kali secara paralel)
    function sbox_layer(s : state_array) return state_array is
        variable t : state_array;
        variable x0, x1, x2, x3, x4 : std_logic_vector(63 downto 0);
    begin
        x0 := s(0); x1 := s(1); x2 := s(2); x3 := s(3); x4 := s(4);
        
        -- Langkah 1: XOR awal
        x0 := x0 xor x4;
        x4 := x4 xor x3;
        x2 := x2 xor x1;
        
        -- Langkah 2: Operasi AND-NOT dan XOR
        t(0) := x0 xor (not x1 and x2);
        t(1) := x1 xor (not x2 and x3);
        t(2) := x2 xor (not x3 and x4);
        t(3) := x3 xor (not x4 and x0);
        t(4) := x4 xor (not x0 and x1);
        
        -- Langkah 3: XOR akhir
        t(1) := t(1) xor t(0);
        t(0) := t(0) xor t(4);
        t(3) := t(3) xor t(2);
        t(2) := not t(2);
        
        return t;
    end function;
    
    -- Implementasi Linear diffusion layer
    function linear_layer(s : state_array) return state_array is
        variable t : state_array;
    begin
        t(0) := s(0) xor rotate_right(s(0), 19) xor rotate_right(s(0), 28);
        t(1) := s(1) xor rotate_right(s(1), 61) xor rotate_right(s(1), 39);
        t(2) := s(2) xor rotate_right(s(2), 1)  xor rotate_right(s(2), 6);
        t(3) := s(3) xor rotate_right(s(3), 10) xor rotate_right(s(3), 17);
        t(4) := s(4) xor rotate_right(s(4), 7)  xor rotate_right(s(4), 41);
        return t;
    end function;

end package body ascon_pkg;
