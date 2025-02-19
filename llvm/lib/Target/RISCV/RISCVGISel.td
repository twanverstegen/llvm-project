//===-- RISCVGIsel.td - RISC-V GlobalISel Patterns ---------*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
/// \file
/// This file contains patterns that are relevant to GlobalISel, including
/// GIComplexOperandMatcher definitions for equivalent SelectionDAG
/// ComplexPatterns.
//
//===----------------------------------------------------------------------===//

include "RISCV.td"
include "RISCVCombine.td"

def simm12Plus1 : ImmLeaf<XLenVT, [{
    return (isInt<12>(Imm) && Imm != -2048) || Imm == 2048;}]>;
def simm12Plus1i32 : ImmLeaf<i32, [{
    return (isInt<12>(Imm) && Imm != -2048) || Imm == 2048;}]>;

def simm12i32 : ImmLeaf<i32, [{return isInt<12>(Imm);}]>;

def uimm5i32 : ImmLeaf<i32, [{return isUInt<5>(Imm);}]>;

// FIXME: This doesn't check that the G_CONSTANT we're deriving the immediate
// from is only used once
def simm12Minus1Nonzero : ImmLeaf<XLenVT, [{
  return (Imm >= -2049 && Imm < 0) || (Imm > 0 && Imm <= 2046);}]>;

def simm12Minus1NonzeroNonNeg1 : ImmLeaf<XLenVT, [{
  return (Imm >= -2049 && Imm < -1) || (Imm > 0 && Imm <= 2046);}]>;

// Return an immediate value plus 1.
def ImmPlus1 : SDNodeXForm<imm, [{
  return CurDAG->getTargetConstant(N->getSExtValue() + 1, SDLoc(N),
                                   N->getValuePtrVTpe(0));}]>;

def GINegImm : GICustomOperandRenderer<"renderNegImm">,
  GISDNodeXFormEquiv<NegImm>;

def GIImmPlus1 :
  GICustomOperandRenderer<"renderImmPlus1">,
  GISDNodeXFormEquiv<ImmPlus1>;

def GIAddrRegImm :
  GIComplexOperandMatcher<s32, "selectAddrRegImm">,
  GIComplexPatternEquiv<AddrRegImm>;

// Convert from i32 immediate to i64 target immediate to make SelectionDAG type
// checking happy so we can use ADDIW which expects an XLen immediate.
def as_i64imm : SDNodeXForm<imm, [{
  return CurDAG->getTargetConstant(N->getSExtValue(), SDLoc(N), MVT::i64);
}]>;
def gi_as_i64imm : GICustomOperandRenderer<"renderImm">,
  GISDNodeXFormEquiv<as_i64imm>;

def gi_trailing_zero : GICustomOperandRenderer<"renderTrailingZeros">,
  GISDNodeXFormEquiv<TrailingZeros>;

// FIXME: This is labelled as handling 's32', however the ComplexPattern it
// refers to handles both i32 and i64 based on the HwMode. Currently this LLT
// parameter appears to be ignored so this pattern works for both, however we
// should add a LowLevelTypeByHwMode, and use that to define our XLenLLT instead
// here.
def ShiftMaskGI :
    GIComplexOperandMatcher<s32, "selectShiftMask">,
    GIComplexPatternEquiv<shiftMaskXLen>;

def gi_sh1add_op : GIComplexOperandMatcher<s32, "selectSHXADDOp<1>">,
                   GIComplexPatternEquiv<sh1add_op>;
def gi_sh2add_op : GIComplexOperandMatcher<s32, "selectSHXADDOp<2>">,
                   GIComplexPatternEquiv<sh2add_op>;
def gi_sh3add_op : GIComplexOperandMatcher<s32, "selectSHXADDOp<3>">,
                   GIComplexPatternEquiv<sh3add_op>;

def gi_sh1add_uw_op : GIComplexOperandMatcher<s32, "selectSHXADD_UWOp<1>">,
                      GIComplexPatternEquiv<sh1add_uw_op>;
def gi_sh2add_uw_op : GIComplexOperandMatcher<s32, "selectSHXADD_UWOp<2>">,
                      GIComplexPatternEquiv<sh2add_uw_op>;
def gi_sh3add_uw_op : GIComplexOperandMatcher<s32, "selectSHXADD_UWOp<3>">,
                      GIComplexPatternEquiv<sh3add_uw_op>;

// FIXME: Canonicalize (sub X, C) -> (add X, -C) earlier.
def : Pat<(XLenVT (sub GPR:$rs1, simm12Plus1:$imm)),
          (ADDI GPR:$rs1, (NegImm simm12Plus1:$imm))>;

let Predicates = [IsRV64] in {
def : Pat<(i32 (add GPR:$rs1, GPR:$rs2)), (ADDW GPR:$rs1, GPR:$rs2)>;
def : Pat<(i32 (sub GPR:$rs1, GPR:$rs2)), (SUBW GPR:$rs1, GPR:$rs2)>;

def : Pat<(i32 (add GPR:$rs1, simm12i32:$imm)),
          (ADDIW GPR:$rs1, (i64 (as_i64imm $imm)))>;
def : Pat<(i32 (sub GPR:$rs1, simm12Plus1i32:$imm)),
          (ADDIW GPR:$rs1, (i64 (NegImm $imm)))>;

def : Pat<(i32 (shl GPR:$rs1, (i32 GPR:$rs2))), (SLLW GPR:$rs1, GPR:$rs2)>;
def : Pat<(i32 (sra GPR:$rs1, (i32 GPR:$rs2))), (SRAW GPR:$rs1, GPR:$rs2)>;
def : Pat<(i32 (srl GPR:$rs1, (i32 GPR:$rs2))), (SRLW GPR:$rs1, GPR:$rs2)>;

def : Pat<(i32 (shl GPR:$rs1, uimm5i32:$imm)),
          (SLLIW GPR:$rs1, (i64 (as_i64imm $imm)))>;
def : Pat<(i32 (sra GPR:$rs1, uimm5i32:$imm)),
          (SRAIW GPR:$rs1, (i64 (as_i64imm $imm)))>;
def : Pat<(i32 (srl GPR:$rs1, uimm5i32:$imm)),
          (SRLIW GPR:$rs1, (i64 (as_i64imm $imm)))>;

def : Pat<(i64 (sext i32:$rs)), (ADDIW GPR:$rs, 0)>;
}

let Predicates = [HasStdExtMOrZmmul, IsRV64] in {
def : Pat<(i32 (mul GPR:$rs1, GPR:$rs2)), (MULW GPR:$rs1, GPR:$rs2)>;
}

let Predicates = [HasStdExtM, IsRV64] in {
def : Pat<(i32 (sdiv GPR:$rs1, GPR:$rs2)), (DIVW GPR:$rs1, GPR:$rs2)>;
def : Pat<(i32 (srem GPR:$rs1, GPR:$rs2)), (REMW GPR:$rs1, GPR:$rs2)>;
def : Pat<(i32 (udiv GPR:$rs1, GPR:$rs2)), (DIVUW GPR:$rs1, GPR:$rs2)>;
def : Pat<(i32 (urem GPR:$rs1, GPR:$rs2)), (REMUW GPR:$rs1, GPR:$rs2)>;
}

let Predicates = [HasStdExtZba, IsRV64] in {
// This pattern is put here due to the fact that i32 is not a legal type
// in SDISel for RV64, which is not the case in GISel.
def : Pat<(shl (i64 (zext i32:$rs1)), uimm5:$shamt),
          (SLLI_UW GPR:$rs1, uimm5:$shamt)>;

def : Pat<(i64 (zext i32:$rs)), (ADD_UW GPR:$rs, (XLenVT X0))>;
} // Predicates = [HasStdExtZba, IsRV64]

let Predicates = [IsRV64, NotHasStdExtZba] in
def: Pat<(i64 (zext i32:$rs)), (SRLI (SLLI GPR:$rs, 32), 32)>;

// Ptr type used in patterns with GlobalISelEmitter
def PtrVT : PtrValueTypeByHwMode<XLenVT, 0>;

// Define pattern expansions for pointer ult/slt conditional codes
def : Pat<(XLenVT (setult (PtrVT GPR:$rs1), simm12:$imm12)),
          (SLTIU GPR:$rs1, simm12:$imm12)>;
def : Pat<(XLenVT (setult (PtrVT GPR:$rs1), (PtrVT GPR:$rs2))),
          (SLTU GPR:$rs1, GPR:$rs2)>;
def : Pat<(XLenVT (setlt (PtrVT GPR:$rs1), simm12:$imm12)),
          (SLTI GPR:$rs1, simm12:$imm12)>;
def : Pat<(XLenVT (setlt (PtrVT GPR:$rs1), (PtrVT GPR:$rs2))),
          (SLT GPR:$rs1, GPR:$rs2)>;

// Define pattern expansions for setcc operations that aren't directly
// handled by a RISC-V instruction.
foreach Ty = [PtrVT, XLenVT] in {
def : Pat<(XLenVT (seteq (Ty GPR:$rs1), (Ty 0))), (SLTIU GPR:$rs1, 1)>;
def : Pat<(XLenVT (seteq (Ty GPR:$rs1), (Ty simm12Plus1:$imm12))),
          (SLTIU (ADDI GPR:$rs1, (NegImm simm12Plus1:$imm12)), 1)>;
def : Pat<(XLenVT (seteq (Ty GPR:$rs1), (Ty GPR:$rs2))),
          (SLTIU (XOR GPR:$rs1, GPR:$rs2), 1)>;
def : Pat<(XLenVT (setne (Ty GPR:$rs1), (Ty 0))), (SLTU (XLenVT X0), GPR:$rs1)>;
def : Pat<(XLenVT (setne (Ty GPR:$rs1), (Ty simm12Plus1:$imm12))),
          (SLTU (XLenVT X0), (ADDI GPR:$rs1, (NegImm simm12Plus1:$imm12)))>;
def : Pat<(XLenVT (setne (Ty GPR:$rs1), (Ty GPR:$rs2))),
          (SLTU (XLenVT X0), (XOR GPR:$rs1, GPR:$rs2))>;
def : Pat<(XLenVT (setugt (Ty GPR:$rs1), (Ty simm12Minus1NonzeroNonNeg1:$imm))),
          (XORI (SLTIU GPR:$rs1,
                       (ImmPlus1 simm12Minus1NonzeroNonNeg1:$imm)), 1)>;
def : Pat<(XLenVT (setugt (Ty GPR:$rs1), (Ty GPR:$rs2))),
          (SLTU GPR:$rs2, GPR:$rs1)>;
def : Pat<(XLenVT (setgt (Ty GPR:$rs1), (Ty simm12Minus1Nonzero:$imm))),
          (XORI (SLTI GPR:$rs1, (ImmPlus1 simm12Minus1Nonzero:$imm)), 1)>;
def : Pat<(XLenVT (setgt (Ty GPR:$rs1), (Ty GPR:$rs2))),
          (SLT GPR:$rs2, GPR:$rs1)>;
def : Pat<(XLenVT (setuge (XLenVT GPR:$rs1), (Ty simm12:$imm))),
          (XORI (SLTIU GPR:$rs1, simm12:$imm), 1)>;
def : Pat<(XLenVT (setuge (Ty GPR:$rs1), (Ty GPR:$rs2))),
          (XORI (SLTU GPR:$rs1, GPR:$rs2), 1)>;
def : Pat<(XLenVT (setge (Ty GPR:$rs1), (Ty simm12:$imm))),
          (XORI (SLTI GPR:$rs1, simm12:$imm), 1)>;
def : Pat<(XLenVT (setge (Ty GPR:$rs1), (Ty GPR:$rs2))),
          (XORI (SLT GPR:$rs1, GPR:$rs2), 1)>;
def : Pat<(XLenVT (setule (Ty GPR:$rs1), (Ty simm12Minus1NonzeroNonNeg1:$imm))),
          (SLTIU GPR:$rs1, (ImmPlus1 simm12Minus1NonzeroNonNeg1:$imm))>;
def : Pat<(XLenVT (setule (Ty GPR:$rs1), (Ty GPR:$rs2))),
          (XORI (SLTU GPR:$rs2, GPR:$rs1), 1)>;
def : Pat<(XLenVT (setle (Ty GPR:$rs1), (Ty simm12Minus1Nonzero:$imm))),
          (SLTI GPR:$rs1, (ImmPlus1 simm12Minus1Nonzero:$imm))>;
def : Pat<(XLenVT (setle (Ty GPR:$rs1), (Ty GPR:$rs2))),
          (XORI (SLT GPR:$rs2, GPR:$rs1), 1)>;
}

// Define pattern expansions for load/extload and store/truncstore operations
// for ptr return type
let Predicates = [IsRV32] in {
def : LdPat<load, LW, PtrVT>;
def : StPat<store, SW, GPR, PtrVT>;
}

let Predicates = [IsRV64] in {
def : LdPat<load, LD, PtrVT>;
def : StPat<store, SD, GPR, PtrVT>;

// Define pattern expansions for rv64 load/extloads and store/truncstore
// operations for i32 return type
def : LdPat<sextloadi8, LB, i32>;
def : LdPat<extloadi8, LBU, i32>;
def : LdPat<zextloadi8, LBU, i32>;
def : LdPat<sextloadi16, LH, i32>;
def : LdPat<extloadi16, LH, i32>;
def : LdPat<zextloadi16, LHU, i32>;
def : LdPat<load, LW, i32>;

def : StPat<truncstorei8, SB, GPR, i32>;
def : StPat<truncstorei16, SH, GPR, i32>;
def : StPat<store, SW, GPR, i32>;
} // Predicates = [IsRV64]
