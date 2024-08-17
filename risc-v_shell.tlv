\m4_TLV_version 1d: tl-x.org
\SV
   // This code can be found in: https://github.com/stevehoover/LF-Building-a-RISC-V-CPU-Core/risc-v_shell.tlv
   
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/LF-Building-a-RISC-V-CPU-Core/main/lib/risc-v_shell_lib.tlv'])



   //---------------------------------------------------------------------------------
   // /====================\
   // | Sum 1 to 9 Program |
   // \====================/
   //
   // Program to test RV32I
   // Add 1,2,3,...,9 (in that order).
   //
   // Regs:
   //  x12 (a2): 10
   //  x13 (a3): 1..10
   //  x14 (a4): Sum
   // 
   m4_asm(ADDI, x14, x0, 0)             // Initialize sum register a4 with 0
   m4_asm(ADDI, x12, x0, 1010)          // Store count of 10 in register a2.
   m4_asm(ADDI, x13, x0, 1)             // Initialize loop count register a3 with 0
   // Loop:
   m4_asm(ADD, x14, x13, x14)           // Incremental summation
   m4_asm(ADDI, x13, x13, 1)            // Increment loop count by 1
   m4_asm(BLT, x13, x12, 1111111111000) // If a3 is less than a2, branch to label named <loop>
   // Test result value in x14, and set x31 to reflect pass/fail.
   m4_asm(ADDI, x30, x14, 111111010100) // Subtract expected value of 44 to set x30 to 1 if and only iff the result is 45 (1 + 2 + ... + 9).
   m4_asm(BGE, x0, x0, 0) // Done. Jump to itself (infinite loop). (Up to 20-bit signed immediate plus implicit 0 bit (unlike JALR) provides byte address; last immediate bit should also be 0)
   m4_asm_end()
   m4_define(['M4_MAX_CYC'], 50)
   //---------------------------------------------------------------------------------


\SV
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)
   /* verilator lint_on WIDTH */
\TLV

   // --- Program Counter and Instruction Fetch ---
   $reset = *reset;               // Get the reset signal from Makerchip
   $pc[31:0] =  >>1$next_pc[31:0]+4; // Calculate the current PC (delayed by one cycle)
   $next_pc[31:0] = $reset ? 1'b0: $pc[31:0]; // Next PC is either 0 (on reset) or PC+4
   `READONLY_MEM($pc, $$instr[31:0]); // Fetch instruction from read-only memory

   // --- Instruction Decoding ---
   // Determine instruction type based on opcode bits [6:2]
   $is_u_instr = $instr[6:2] == 5'b00101 || $instr[6:2] == 5'b01101;  // U-type (e.g., lui, auipc)
   $is_i_instr = $instr[6:2] == 5'b00000 || $instr[6:2] == 5'b00001 ||
                 $instr[6:2] == 5'b00100 || $instr[6:2] == 5'b00110 ||
                 $instr[6:2] == 5'b11001; // I-type (e.g., addi, jalr)
   $is_r_instr = $instr[6:2] == 5'b01011 || $instr[6:2] == 5'b01100 ||
                 $instr[6:2] == 5'b01110 || $instr[6:2] == 5'b10100; // R-type (e.g., add, sub)
   $is_s_instr = $instr[6:2] == 5'b01000 || $instr[6:2] == 5'b01001;  // S-type (e.g., sw, sb)
   $is_b_instr = $instr[6:2] == 5'b11000;  // B-type (e.g., beq, bne)
   $is_j_instr = $instr[6:2] == 5'b11011;  // J-type (e.g., jal)

   // --- Extract Instruction Fields ---
   $rs2[4:0] = $instr[24:20];     // Source register 2
   $funct3[2:0] = $instr[14:12];   // Function code (for R, I, S, B types)
   $rs1[4:0] = $instr[19:15];     // Source register 1
   $rd[4:0] = $instr[11:7];       // Destination register
   $opcode[6:0] = $instr[6:0];     // Opcode

   // --- Determine Validity of Instruction Fields ---
   $rs2_valid = $is_r_instr || $is_s_instr || $is_b_instr;
   $funct3_valid = $is_r_instr || $is_s_instr || $is_b_instr || $is_i_instr;
   $rs1_valid  = $is_r_instr || $is_s_instr || $is_b_instr || $is_i_instr;
   $rd_valid   = $is_r_instr || $is_i_instr || $is_u_instr || $is_j_instr;
   $imm_valid  = $is_i_instr || $is_s_instr || $is_b_instr || $is_u_instr || $is_j_instr;

   `BOGUS_USE($rd $rd_valid $rs1 $rs1_valid ...) // Prevent unused signal warnings

   // --- Immediate Value Extraction ---
   // Construct the immediate value based on instruction type
   $imm[31:0] = $is_i_instr ? {{21{$instr[31]}}, $instr[30:20]} :
                $is_s_instr ? {{21{$instr[31]}}, $instr[30:25], $instr[11:7]} :
                $is_b_instr ? {{20{$instr[31]}}, $instr[7], $instr[30:25], $instr[11:8],1'b0} :
                $is_u_instr ? {$instr[31:12], 12'h000} :
                $is_j_instr ? {{12{$instr[31]}}, $instr[19:12], $instr[20], $instr[30:21], 1'b0} :
                32'h0 ;

   // --- Instruction Decode for Supported Instructions ---
   $dec_bits[10:0]   =  {$funct7[5], $funct3, $opcode}; // Combine fields for decoding

   // Branch instructions
   $is_beq           =  $dec_bits ==? 11'bx_000_1100011;
   $is_bne           =  $dec_bits ==? 11'bx_001_1100011;
   $is_blt           =  $dec_bits ==? 11'bx_100_1100011;
   $is_bge           =  $dec_bits ==? 11'bx_101_1100011;
   $is_bltu          =  $dec_bits ==? 11'bx_110_1100011;
   $is_bgeu          =  $dec_bits ==? 11'bx_111_1100011;

   // Arithmetic instructions
   $is_addi          =  $dec_bits ==? 11'bx_000_0010011;
   $is_add           =  $dec_bits ==? 11'b0_000_0110011;

   `BOGUS_USE($rd $rd_valid $rs1 $rs1_valid ...) // Prevent unused signal warnings

   // --- Execute ---
   $result[31:0] =   $is_addi ?  $src1_value + $imm :  // Execute addi
                     $is_add  ?  $src1_value + $src2_value : // Execute add
                     32'bx; // Default: undefined result

   // --- Writeback ---
   $rf_wr_en            =     $rd_valid && ($rd != 5'b0); // Enable register write if valid destination
   $rf_wr_index[4:0]    =     $rd;                      // Destination register index
   $rf_wr_data[31:0]    =     $is_load ? $ld_data : $result;  // Write load data or ALU result

   // --- Branch Handling ---
   $taken_br   =  $is_beq  ?  ($src1_value == $src2_value) :
                  $is_bne  ?  ($src1_value != $src2_value) :
                  $is_blt  ?  (($src1_value < $src2_value)  ^ ($src1_value[31] != $src2_value[31])) :
                  $is_bge  ?  (($src1_value >= $src2_value) ^ ($src1_value[31] != $src2_value[31])) :
                  $is_bltu ?  ($src1_value < $src2_value)  :
                  $is_bgeu ?  ($src1_value >= $src2_value) :
                  1'b0; // Default: not taken
   $br_tgt_pc[31:0]  =  $pc + $imm;  // Calculate branch target address

   // --- Makerchip Integration ---
   // Assert these to end simulation (before Makerchip cycle limit).
   m4+tb()
   *failed = *cyc_cnt > M4_MAX_CYC;

   // --- Instantiate Components ---
   m4+rf(32, 32, $reset, $rd_valid && ($rd != 5'b0), $rd, $is_load ? $ld_data : $result, $rs1_valid, $rs1, $src1_value[31:0], $rs2_valid, $rs2, $src2_value[31:0]) // Register file
   //m4+rf(32, 32, $reset, $wr_en, $wr_index[4:0], $wr_data[31:0], $rd_en1, $rd_index1[4:0], $rd_data1, $rd_en2, $rd_index2[4:0], $rd_data2) // Alternative RF instantiation
   //m4+dmem(32, 32, $reset, $addr[4:0], $wr_en, $wr_data[31:0], $rd_en, $rd_data) // Data memory (not used in this code)
   m4+cpu_viz() // CPU visualization component

\SV
   endmodule 
