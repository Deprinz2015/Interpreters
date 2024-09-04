pub const Instruction = enum(u8) {
    CONSTANTS_DONE,
    CONSTANT,
    NUMBER,
    ADD,
    SUB,
    MUL,
    DIV,
    POP,
    PRINT,
};
