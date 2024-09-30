----------------------------------------------------------------------------------
-- Company:
-- Engineer: Walter, Zhu
--
-- Create Date: 26.09.2024 16:55:00
-- Design Name:
-- Module Name: axi LTC1688 DAC
-- Project Name:
-- Target Devices:
-- Tool Versions:
-- Description:
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use ieee.numeric_std.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
-- library UNISIM;
-- use UNISIM.VComponents.all;

use work.tb_utils_pkg.all;

entity axi_ltc1688_dac is
    generic (
        -- parameters for Axi Slave Port
        c_s00_axi_data_width : integer := 32;
        c_s00_axi_addr_width : integer := 5;

        reset_width : integer := 2;
        reset_index : integer := 0;

        -- debug mode for simulation with tb
        debug_mode_tb : integer := 0;
        -- axi-regs to be used in simulation

        dac_data_width   : integer := 14;
        axis_tdata_width : integer := 16;

        fifo_depth : integer := 16
        );
    port (
        -- User Ports:
        -- for now we dont need any reset
        rstn : in std_logic_vector(reset_width - 1 downto 0);

        -- PLL-Signals/Clock-Signals:
        wr_clk : in std_logic;          -- system clock 125 MHz
        rd_clk : in std_logic;          -- clock for dac board 50 MHz

        -- Connections to LTC1688 DAC Board:
        ltc1688_dac_clk   : out std_logic;  --by default 50 MHz
        ltc1688_dac_data  : out std_logic_vector(dac_data_width - 1 downto 0);
        ltc1688_dac_ready : out std_logic;
        ltc1688_dac_valid : in  std_logic;  --not in use, maybe in the future?

        -- sample trigger for ADC-Sampling
        sample_trigger_out : out std_logic;

        -- Ports of Axi-Stream Master Slave-Side:
        -- Channel 1:
        s00_axis_tready : out std_logic;
        s00_axis_tvalid : in  std_logic;
        s00_axis_tdata  : in  std_logic_vector(axis_tdata_width - 1 downto 0);
        s00_axis_tuser  : in  std_logic_vector(c_s00_axi_data_width - 1 downto 0);

        -- Ports of Axi Slave Bus Interface S00_AXI
        s_axi_aresetn : in  std_logic;
        s_axi_awaddr  : in  std_logic_vector(c_s00_axi_addr_width - 1 downto 0);
        s_axi_awprot  : in  std_logic_vector(2 downto 0);
        s_axi_awvalid : in  std_logic;
        s_axi_awready : out std_logic;
        s_axi_wdata   : in  std_logic_vector(c_s00_axi_data_width - 1 downto 0);
        s_axi_wstrb   : in  std_logic_vector((c_s00_axi_data_width / 8) - 1 downto 0);
        s_axi_wvalid  : in  std_logic;
        s_axi_wready  : out std_logic;
        s_axi_bresp   : out std_logic_vector(1 downto 0);
        s_axi_bvalid  : out std_logic;
        s_axi_bready  : in  std_logic;
        s_axi_araddr  : in  std_logic_vector(c_s00_axi_addr_width - 1 downto 0);
        s_axi_arprot  : in  std_logic_vector(2 downto 0);
        s_axi_arvalid : in  std_logic;
        s_axi_arready : out std_logic;
        s_axi_rdata   : out std_logic_vector(c_s00_axi_data_width - 1 downto 0);
        s_axi_rresp   : out std_logic_vector(1 downto 0);
        s_axi_rvalid  : out std_logic;
        s_axi_rready  : in  std_logic
        );
end entity axi_ltc1688_dac;

architecture behavioral of axi_ltc1688_dac is

    -- component declaration
    component axi_red_pitaya_ltc1688_dac_s_axi is
        generic (
            c_s_axi_data_width : integer := 32;
            c_s_axi_addr_width : integer := 5
            );
        port (
            s_axi_use_ltc_valid : out std_logic;
            -- axi slave regs
            s_axi_aclk          : in  std_logic;
            s_axi_aresetn       : in  std_logic;
            s_axi_awaddr        : in  std_logic_vector(c_s_axi_addr_width - 1 downto 0);
            s_axi_awprot        : in  std_logic_vector(2 downto 0);
            s_axi_awvalid       : in  std_logic;
            s_axi_awready       : out std_logic;
            s_axi_wdata         : in  std_logic_vector(c_s_axi_data_width - 1 downto 0);
            s_axi_wstrb         : in  std_logic_vector((c_s_axi_data_width / 8) - 1 downto 0);
            s_axi_wvalid        : in  std_logic;
            s_axi_wready        : out std_logic;
            s_axi_bresp         : out std_logic_vector(1 downto 0);
            s_axi_bvalid        : out std_logic;
            s_axi_bready        : in  std_logic;
            s_axi_araddr        : in  std_logic_vector(c_s_axi_addr_width - 1 downto 0);
            s_axi_arprot        : in  std_logic_vector(2 downto 0);
            s_axi_arvalid       : in  std_logic;
            s_axi_arready       : out std_logic;
            s_axi_rdata         : out std_logic_vector(c_s_axi_data_width - 1 downto 0);
            s_axi_rresp         : out std_logic_vector(1 downto 0);
            s_axi_rvalid        : out std_logic;
            s_axi_rready        : in  std_logic
            );
    end component axi_red_pitaya_ltc1688_dac_s_axi;

    signal s_axi_use_ltc_valid : std_logic := '0';

    signal i_wdata   : std_logic_vector(dac_data_width - 1 downto 0) := (others => '0');
    signal i_wr      : std_logic                                     := '0';  --write request
    signal o_wr_full : std_logic                                     := '0';  --write full flag

    signal wr_ptr_bin         : unsigned(ptr_width downto 0)   := (others => '0');  -- write pointer
    signal wr_ptr_bin_next    : unsigned(ptr_width downto 0)   := (others => '0');  -- write pointer
    signal wr_ptr_gray        : unsigned(ptr_width downto 0)   := (others => '0');  -- write pointer
    signal wr_ptr_gray_next   : unsigned(ptr_width downto 0)   := (others => '0');  -- write pointer
    signal waclk_rd_ptr_gray2 : unsigned(ptr_width downto 0)   := (others => '0');  -- write pointer
    signal waclk_rd_ptr_gray1 : unsigned(ptr_width downto 0)   := (others => '0');  -- write pointer
    signal wr_addr            : unsigned(ptr_width-1 downto 0) := (others => '0');  -- write pointer

    signal o_rdata    : std_logic_vector(dac_data_width - 1 downto 0) := (others => '0');
    signal i_rd       : std_logic                                     := '0';  --read request
    signal o_rd_empty : std_logic                                     := '0';  --read empty flag

    signal rd_ptr_bin         : unsigned(ptr_width downto 0)   := (others => '0');  --read pointer
    signal rd_ptr_bin_next    : unsigned(ptr_width downto 0)   := (others => '0');  --read pointer
    signal rd_ptr_gray        : unsigned(ptr_width downto 0)   := (others => '0');  --read pointer
    signal rd_ptr_gray_next   : unsigned(ptr_width downto 0)   := (others => '0');  --read pointer
    signal raclk_wr_ptr_gray2 : unsigned(ptr_width downto 0)   := (others => '0');  --read pointer
    signal raclk_wr_ptr_gray1 : unsigned(ptr_width downto 0)   := (others => '0');  --read pointer
    signal rd_addr            : unsigned(ptr_width-1 downto 0) := (others => '0');  --read pointer

    signal wfull_next  : std_logic := '0';
    signal rempty_next : std_logic := '0';

    type mem_type is array (0 to fifo_depth-1) of std_logic_vector(dac_data_width - 1 downto 0);
    signal mem : mem_type := (others => (others => '0'));  -- first others is to set all elements in the array, each element of the array is a std_logic_vector

begin
    -- Instantiation of Axi Bus Interface S00_AXI
    axi_red_pitaya_ltc1688_dac_s_axi_inst : component axi_red_pitaya_ltc1688_dac_s_axi
        generic map (
            c_s_axi_data_width => c_s00_axi_data_width,
            c_s_axi_addr_width => c_s00_axi_addr_width
            )
        port map (
            s_axi_use_ltc_valid => s_axi_use_ltc_valid,

            -- axi slave port
            s_axi_aclk    => aclk,
            s_axi_aresetn => s_axi_aresetn,
            s_axi_awaddr  => s_axi_awaddr,
            s_axi_awprot  => s_axi_awprot,
            s_axi_awvalid => s_axi_awvalid,
            s_axi_awready => s_axi_awready,
            s_axi_wdata   => s_axi_wdata,
            s_axi_wstrb   => s_axi_wstrb,
            s_axi_wvalid  => s_axi_wvalid,
            s_axi_wready  => s_axi_wready,
            s_axi_bresp   => s_axi_bresp,
            s_axi_bvalid  => s_axi_bvalid,
            s_axi_bready  => s_axi_bready,
            s_axi_araddr  => s_axi_araddr,
            s_axi_arprot  => s_axi_arprot,
            s_axi_arvalid => s_axi_arvalid,
            s_axi_arready => s_axi_arready,
            s_axi_rdata   => s_axi_rdata,
            s_axi_rresp   => s_axi_rresp,
            s_axi_rvalid  => s_axi_rvalid,
            s_axi_rready  => s_axi_rready
            );

------ write section -----

--Cross the read Gray pointer into the write clock domain
    rd_ptr_into_wr_aclk_domain : process(aclk, rstn) is
    begin
        if(rstn(reset_index) = '0') then
            waclk_rd_ptr_gray2 <= (others => '0');
            waclk_rd_ptr_gray1 <= (others => '0');
        elsif rising_edge(aclk) then
            waclk_rd_ptr_gray1 <= rd_ptr_gray;
            waclk_rd_ptr_gray2 <= waclk_rd_ptr_gray1;
        end if;
        -- if rising_edge(aclk) then
        --     if(rstn(reset_index) = '0') then
        --         waclk_rd_ptr_gray2 <= (others => '0');
        --         waclk_rd_ptr_gray1 <= (others => '0');
        --     else
        --         waclk_rd_ptr_gray1 <= rd_ptr_gray;
        --         waclk_rd_ptr_gray2 <= waclk_rd_ptr_gray1;
        --     end if;
        -- end if;

    end process rd_ptr_into_wr_aclk_domain;

    -- increment wr_ptr_bin if i_wr/valid is high and o_wr_full/!ready is low
    wr_ptr_bin_next  <= (wr_ptr_bin+1) when (i_wr = '1' and o_wr_full = '0') else (wr_ptr_bin+0);
    wr_ptr_gray_next <= Bin2Gray(wr_ptr_bin_next);

    wr_addr <= wr_ptr_bin(ptr_width-1 downto 0);

    wr_ptr_bin_gray : process(aclk, rstn) is
    begin
        if(rstn(reset_index) = '0') then
            wr_ptr_bin  <= (others => '0');
            wr_ptr_gray <= (others => '0');
        elsif rising_edge(aclk) then
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end if;
        -- if rising_edge(aclk) then
        --     if(rstn(reset_index) = '0') then
        --         wr_ptr_bin  <= (others => '0');
        --         wr_ptr_gray <= (others => '0');
        --     else
        --         wr_ptr_bin  <= wr_ptr_bin_next;
        --         wr_ptr_gray <= wr_ptr_gray_next;
        --     end if;
        -- end if;

    end process wr_ptr_bin_gray;

    -- fifo is full when wr_ptr - rd_ptr = 2^ptr_width-1, which means that the MSB is flipped and the rest of the bits are equal between the two pointers
    -- in gray code format, the two upper bits are flipped, bc of the right shift, the rest of them are equal between the two pointers
    --wfull_next <= '1' when (Gray2Bin(wr_ptr_gray_next)- Gray2Bin(waclk_rd_ptr_gray2) = 1) else '0';
    wfull_next <= '1' when (wr_ptr_gray_next = (not(waclk_rd_ptr_gray2(ptr_width downto ptr_width-1)) & waclk_rd_ptr_gray2(ptr_width-2 downto 0))) else '0';

    i_wr <= s00_axis_tvalid;

    i_wdata <= s00_axis_tdata(dac_data_width - 1 downto 0);

    s00_axis_tready <= not(o_wr_full);

-- Calculate whether or not the register will be full on the next clock
    o_wr_full_proc : process(aclk, rstn) is
    begin
        if(rstn(reset_index) = '0') then
            o_wr_full <= '0';
        elsif rising_edge(aclk) then
            o_wr_full <= wfull_next;
        end if;
    -- if rising_edge(aclk) then
    --     if(rstn(reset_index) = '0') then
    --         o_wr_full <= '0';
    --     else
    --         o_wr_full <= wfull_next;
    --     end if;
    -- end if;
    end process o_wr_full_proc;

-- write data to fifo
    write_to_fifo_proc : process(aclk) is
    begin
        if rising_edge(aclk) then
            if(i_wr = '1' and o_wr_full = '0') then
                mem(to_integer(wr_addr)) <= i_wdata;
            end if;
        end if;
    end process write_to_fifo_proc;

------ read section -----

-- Cross the write Gray pointer into the read clock domain
    wr_ptr_into_rd_aclk_domain : process(aclk_2, rstn) is
    begin
        if(rstn(reset_index) = '0') then
            raclk_wr_ptr_gray2 <= (others => '0');
            raclk_wr_ptr_gray1 <= (others => '0');
        elsif rising_edge(aclk_2) then
            raclk_wr_ptr_gray1 <= wr_ptr_gray;
            raclk_wr_ptr_gray2 <= raclk_wr_ptr_gray1;
        end if;
        -- if rising_edge(aclk_2) then
        --     if(rstn(reset_index) = '0') then
        --         raclk_wr_ptr_gray2 <= (others => '0');
        --         raclk_wr_ptr_gray1 <= (others => '0');
        --     else
        --         raclk_wr_ptr_gray1 <= wr_ptr_gray;
        --         raclk_wr_ptr_gray2 <= raclk_wr_ptr_gray1;
        --     end if;
        -- end if;

    end process wr_ptr_into_rd_aclk_domain;

-- read pointer handler
    -- increment rd_ptr_bin if i_rd/valid is high and o_rd_empty/!ready is low
    rd_ptr_bin_next  <= (rd_ptr_bin + 1) when (i_rd = '1' and o_rd_empty = '0') else (rd_ptr_bin + 0);
    rd_ptr_gray_next <= Bin2Gray(rd_ptr_bin_next);

    rd_addr <= rd_ptr_bin(ptr_width-1 downto 0);

    rd_ptr_bin_gray : process(aclk_2, rstn) is
    begin
        if(rstn(reset_index) = '0') then
            rd_ptr_bin  <= (others => '0');
            rd_ptr_gray <= (others => '0');
        elsif rising_edge(aclk_2) then
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end if;
        -- if rising_edge(aclk_2) then
        --     if(rstn(reset_index) = '0') then
        --         rd_ptr_bin  <= (others => '0');
        --         rd_ptr_gray <= (others => '0');
        --     else
        --         rd_ptr_bin  <= rd_ptr_bin_next;
        --         rd_ptr_gray <= rd_ptr_gray_next;
        --     end if;
        -- end if;

    end process rd_ptr_bin_gray;

-- Calculate whether or not the register will be empty on the next clock
    o_rd_empty_proc : process(aclk_2, rstn) is
    begin
        if(rstn(reset_index) = '0') then
            o_rd_empty <= '1';
        elsif rising_edge(aclk_2) then
            o_rd_empty <= rempty_next;
        end if;
    -- if rising_edge(aclk_2) then
    --     if(rstn(reset_index) = '0') then
    --         o_rd_empty <= '0';
    --     else
    --         o_rd_empty <= rempty_next;
    --     end if;
    -- end if;
    end process o_rd_empty_proc;

    -- read data from fifo
    -- read_from_fifo_proc : process(aclk_2, rstn) is
    -- begin
    --     if(rstn(reset_index) = '0') then
    --         o_rdata <= (others => '0');
    --     elsif rising_edge(aclk_2) then
    --         if(i_rd = '1' and o_rd_empty = '0') then
    --             o_rdata <= mem(to_integer(rd_ptr_bin));
    --         end if;
    --     end if;
    -- if rising_edge(aclk_2) then
    --     if(i_rd = '1' and o_rd_empty = '0') then
    --         o_rdata <= mem(rd_ptr_bin);
    --     end if;
    -- end if;
--    end process read_from_fifo_proc;
    o_rdata <= mem(to_integer(rd_addr));

    -- fifo is empty when next read pointer address is equal to write pointer
    rempty_next <= '1' when raclk_wr_ptr_gray2 = rd_ptr_gray_next else '0';

    -- read valid signal always high
    i_rd <= '1' when s_axi_use_ltc_valid = '0' else ltc1688_dac_valid;

    ltc1688_dac_ready <= not(o_rd_empty);
    ltc1688_dac_data  <= o_rdata;
    ltc1688_dac_clk   <= aclk_2;

end architecture behavioral;
