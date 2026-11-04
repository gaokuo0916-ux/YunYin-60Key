create_clock -name sys_clk -period 20.000 [get_ports {sys_clk}]
// External serial input enters a two-register synchronizer.
set_false_path -from [get_ports {key_data}]
set_false_path -from [get_ports {key0_n}]
// Touch serial inputs each enter a two-register synchronizer in the I2C master.
set_false_path -from [get_ports {touch_sda touch_scl touch_int}]
// All display registers really use sys_clk; pixel_phase is DATA/CE, not an
// internal clock. Its external 25MHz waveform is checked in pin-level RTL.
// Use the 50MHz parent as a conservative I/O reference: the actual data launch
// on the odd edge has exactly one 20ns parent period before the next LCD rise.
// This also avoids tagging divider feedback and CE as a second clock domain.
// The 2ns setup / 0ns hold budgets require actual panel/wiring confirmation.
set_output_delay -clock sys_clk -max 2.000 [get_ports {lcd_r[*] lcd_g[*] lcd_b[*] lcd_hs lcd_vs lcd_de}]
set_output_delay -clock sys_clk -min 0.000 [get_ports {lcd_r[*] lcd_g[*] lcd_b[*] lcd_hs lcd_vs lcd_de}]
// These output registers have CE=pixel_phase: they launch only on the falling
// pixel edge (the odd sys_clk edge), never the coincident rising pixel edge.
// Keep the existing setup check. Shift HOLD launch by one 20ns source cycle
// to describe that known clock enable relation; audio/internal paths excluded.
set_multicycle_path -from [get_clocks {sys_clk}] -to [get_ports {lcd_r[*] lcd_g[*] lcd_b[*] lcd_hs lcd_vs lcd_de}] -hold -start 1
// HC-05 serial input enters the new UART's two-flop synchronizer.
set_false_path -from [get_ports {bt_rx}]

// I2S WS/data launch on falling BCLK and are sampled 160ns later. Use the
// 20ns parent-clock budget conservatively (10ns receiver setup allowance).
// This checks pad routing without introducing a generated internal clock.
set_output_delay -clock sys_clk -max 10.000 [get_ports {i2s_lrclk i2s_dout}]
set_output_delay -clock sys_clk -min 0.000 [get_ports {i2s_lrclk i2s_dout}]
set_multicycle_path -from [get_clocks {sys_clk}] -to [get_ports {i2s_lrclk i2s_dout}] -hold -start 1

// SD MISO is sampled through two 50MHz registers; SD clock is <=6.25MHz.
set_false_path -from [get_ports {sd_miso}]
