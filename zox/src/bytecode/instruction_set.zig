pub const Instruction = enum(u8) {
    CONSTANTS_DONE,
    CONSTANT,
    NUMBER,
    TRUE,
    FALSE,
    NIL,
    ADD,
    SUB,
    MUL,
    DIV,
    POP,
    PRINT,
};
