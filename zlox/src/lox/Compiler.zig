const DEBUG_PRINT_CODE = @import("config").chunk_trace;
const LOCAL_COUNT = 256;

const std = @import("std");
const Allocator = std.mem.Allocator;
const StdOut = std.io.getStdOut();
const StdErr = std.io.getStdErr();

const Scanner = @import("Scanner.zig");
const Chunk = @import("Chunk.zig");
const VM = @import("VM.zig");
const Value = @import("value.zig").Value;
const Obj = @import("value.zig").Obj;
const Token = @import("Scanner.zig").Token;
const TokenType = @import("Scanner.zig").TokenType;

const Error = error{
    ParserError,
};

const Parser = struct {
    current: Token,
    previous: Token,
    scanner: Scanner,
    compiling_chunk: *Chunk,
    had_error: bool = false,
    panic_mode: bool = false,
    vm: *VM,
    compiler: *Compiler,
    alloc: Allocator,

    const EmittingByte = union(enum) {
        OPCODE: Chunk.OpCode,
        RAW: u8,
    };

    const Precedence = enum(u8) {
        NONE,
        ASSIGNMENT, // =
        OR, // or
        AND, // and
        EQUALITY, // == !=
        COMPARISON, // < > <= >=
        TERM, // + -
        FACTOR, // * /
        UNARY, // ! -
        CALL, // . ()
        PRIMARY,
    };

    const ParseArguments = struct {
        can_assign: bool = false,
    };
    const ParseFn = *const fn (self: *Parser, arguments: ParseArguments) void;
    const ParseRule = struct {
        prefix: ?ParseFn,
        infix: ?ParseFn,
        precedence: Precedence,
    };

    const rules = std.StaticStringMap(ParseRule).initComptime(.{
        .{ @tagName(TokenType.LEFT_PAREN), .{ .prefix = grouping, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.RIGHT_PAREN), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.LEFT_BRACE), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.RIGHT_BRACE), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.COMMA), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.DOT), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.MINUS), .{ .prefix = unary, .infix = binary, .precedence = .TERM } },
        .{ @tagName(TokenType.PLUS), .{ .prefix = null, .infix = binary, .precedence = .TERM } },
        .{ @tagName(TokenType.SEMICOLON), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.SLASH), .{ .prefix = null, .infix = binary, .precedence = .FACTOR } },
        .{ @tagName(TokenType.STAR), .{ .prefix = null, .infix = binary, .precedence = .FACTOR } },
        .{ @tagName(TokenType.BANG), .{ .prefix = unary, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.BANG_EQUAL), .{ .prefix = null, .infix = binary, .precedence = .EQUALITY } },
        .{ @tagName(TokenType.EQUAL), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.EQUAL_EQUAL), .{ .prefix = null, .infix = binary, .precedence = .EQUALITY } },
        .{ @tagName(TokenType.GREATER), .{ .prefix = null, .infix = binary, .precedence = .COMPARISON } },
        .{ @tagName(TokenType.GREATER_EQUAL), .{ .prefix = null, .infix = binary, .precedence = .COMPARISON } },
        .{ @tagName(TokenType.LESS), .{ .prefix = null, .infix = binary, .precedence = .COMPARISON } },
        .{ @tagName(TokenType.LESS_EQUAL), .{ .prefix = null, .infix = binary, .precedence = .COMPARISON } },
        .{ @tagName(TokenType.IDENTIFIER), .{ .prefix = variable, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.STRING), .{ .prefix = string, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.NUMBER), .{ .prefix = number, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.AND), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.CLASS), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.ELSE), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.FALSE), .{ .prefix = literal, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.FOR), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.FUN), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.IF), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.NIL), .{ .prefix = literal, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.OR), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.PRINT), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.RETURN), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.SUPER), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.THIS), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.TRUE), .{ .prefix = literal, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.VAR), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.WHILE), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.ERROR), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.EOF), .{ .prefix = null, .infix = null, .precedence = .NONE } },
    });

    fn advance(self: *Parser) void {
        self.previous = self.current;
        while (true) {
            self.current = self.scanner.scanToken();

            if (self.current.token_type != .ERROR) {
                break;
            }

            self.emitErrorAtCurrent(self.currentLexeme());
        }
    }

    fn consume(self: *Parser, token_type: TokenType, msg: []const u8) void {
        if (self.current.token_type == token_type) {
            self.advance();
            return;
        }

        self.emitErrorAtCurrent(msg);
    }

    fn match(self: *Parser, token_type: TokenType) bool {
        if (!self.check(token_type)) {
            return false;
        }

        self.advance();
        return true;
    }

    fn check(self: *Parser, token_type: TokenType) bool {
        return self.current.token_type == token_type;
    }

    fn expression(self: *Parser) void {
        self.parsePrecedence(.ASSIGNMENT);
    }

    fn block(self: *Parser) void {
        while (!self.check(.RIGHT_BRACE) and !self.check(.EOF)) {
            self.declaration();
        }

        self.consume(.RIGHT_BRACE, "Expect '}' after Block.");
    }

    fn declaration(self: *Parser) void {
        if (self.match(.VAR)) {
            self.varDeclaration();
        } else {
            self.statement();
        }

        if (self.panic_mode) {
            self.synchronize();
        }
    }

    fn varDeclaration(self: *Parser) void {
        const global = self.parseVariable("Expect variable name.");

        if (self.match(.EQUAL)) {
            self.expression();
        } else {
            self.emitByte(.{ .OPCODE = .NIL });
        }
        self.consume(.SEMICOLON, "Expect ';' after variable declaration.");

        self.defineVariable(global);
    }

    fn statement(self: *Parser) void {
        if (self.match(.PRINT)) {
            self.printStatement();
        } else if (self.match(.LEFT_BRACE)) {
            self.beginScope();
            self.block();
            self.endScope();
        } else if (self.match(.IF)) {
            self.ifStatement();
        } else {
            self.expressionStatement();
        }
    }

    fn printStatement(self: *Parser) void {
        self.expression();
        self.consume(.SEMICOLON, "Expect ';' after value.");
        self.emitByte(.{ .OPCODE = .PRINT });
    }

    fn expressionStatement(self: *Parser) void {
        self.expression();
        self.consume(.SEMICOLON, "Expect ';' after value.");
        self.emitByte(.{ .OPCODE = .POP });
    }

    fn ifStatement(self: *Parser) void {
        self.consume(.LEFT_PAREN, "Expect '(' after 'if'.");
        self.expression();
        self.consume(.RIGHT_PAREN, "Expect ')' after condition.");

        const thenJump = self.emitJump(.{ .OPCODE = .JUMP_IF_FALSE });
        self.emitByte(.{ .OPCODE = .POP });
        self.statement();

        const elseJump = self.emitJump(.{ .OPCODE = .JUMP });

        self.patchJump(thenJump);
        self.emitByte(.{ .OPCODE = .POP });

        if (self.match(.ELSE)) {
            self.statement();
        }
        self.patchJump(elseJump);
    }

    fn literal(self: *Parser, _: ParseArguments) void {
        switch (self.previous.token_type) {
            .TRUE => self.emitByte(.{ .OPCODE = .TRUE }),
            .FALSE => self.emitByte(.{ .OPCODE = .FALSE }),
            .NIL => self.emitByte(.{ .OPCODE = .NIL }),
            else => unreachable,
        }
    }

    fn number(self: *Parser, _: ParseArguments) void {
        const value = std.fmt.parseFloat(f32, self.previousLexeme()) catch {
            std.debug.print("Could not parse a float value from string '{s}'\n", .{self.previousLexeme()});
            unreachable;
        };
        self.emitConstant(.{ .NUMBER = value });
    }

    fn string(self: *Parser, _: ParseArguments) void {
        const previous = self.previousLexeme();
        self.emitConstant(.{ .OBJ = Obj.copyString(self.alloc, previous[1 .. previous.len - 1], self.vm) });
    }

    fn variable(self: *Parser, arguments: ParseArguments) void {
        self.namedVariables(self.previous, arguments.can_assign);
    }

    fn namedVariables(self: *Parser, name: Token, can_assign: bool) void {
        var local = true;
        const arg: u8 = arg: {
            const idx = self.resolveLocal(name);
            if (idx != -1) {
                break :arg @intCast(idx);
            }

            local = false;
            break :arg self.identifierConstant(name);
        };

        const getOp: Chunk.OpCode = if (local) .GET_LOCAL else .GET_GLOBAL;
        const setOp: Chunk.OpCode = if (local) .SET_LOCAL else .SET_GLOBAL;

        if (can_assign and self.match(.EQUAL)) {
            self.expression();
            self.emitBytes(.{ .OPCODE = setOp }, .{ .RAW = arg });
        } else {
            self.emitBytes(.{ .OPCODE = getOp }, .{ .RAW = arg });
        }
    }

    fn unary(self: *Parser, _: ParseArguments) void {
        const token_type = self.previous.token_type;

        self.parsePrecedence(.UNARY);

        switch (token_type) {
            .MINUS => self.emitByte(.{ .OPCODE = .NEGATE }),
            .BANG => self.emitByte(.{ .OPCODE = .NOT }),
            else => unreachable,
        }
    }

    fn binary(self: *Parser, _: ParseArguments) void {
        const operator = self.previous.token_type;
        const rule = getRule(operator);
        self.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

        switch (operator) {
            .PLUS => self.emitByte(.{ .OPCODE = .ADD }),
            .MINUS => self.emitByte(.{ .OPCODE = .SUBTRACT }),
            .STAR => self.emitByte(.{ .OPCODE = .MULTIPLY }),
            .SLASH => self.emitByte(.{ .OPCODE = .DIVIDE }),
            .EQUAL_EQUAL => self.emitByte(.{ .OPCODE = .EQUAL }),
            .LESS => self.emitByte(.{ .OPCODE = .LESS }),
            .GREATER => self.emitByte(.{ .OPCODE = .GREATER }),
            .BANG_EQUAL => self.emitBytes(.{ .OPCODE = .EQUAL }, .{ .OPCODE = .NOT }),
            .LESS_EQUAL => self.emitBytes(.{ .OPCODE = .GREATER }, .{ .OPCODE = .NOT }),
            .GREATER_EQUAL => self.emitBytes(.{ .OPCODE = .LESS }, .{ .OPCODE = .NOT }),
            else => unreachable,
        }
    }

    fn parsePrecedence(self: *Parser, precedence: Precedence) void {
        self.advance();
        const prefix_rule = getRule(self.previous.token_type).prefix;
        if (prefix_rule == null) {
            self.emitError("Expect expression.");
            return;
        }

        const prefix = prefix_rule.?;

        const can_assign = @intFromEnum(precedence) <= @intFromEnum(Precedence.ASSIGNMENT);
        prefix(self, .{ .can_assign = can_assign });

        while (@intFromEnum(precedence) <= @intFromEnum(getRule(self.current.token_type).precedence)) {
            self.advance();
            const infix_rule = getRule(self.previous.token_type).infix;
            if (infix_rule) |infix| {
                infix(self, .{});
            }
        }

        if (can_assign and self.match(.EQUAL)) {
            self.emitError("Invalid assignment target.");
        }
    }

    fn parseVariable(self: *Parser, err_msg: []const u8) u8 {
        self.consume(.IDENTIFIER, err_msg);

        self.declareVariable();
        if (self.compiler.scope_depth > 0) {
            return 0;
        }

        return self.identifierConstant(self.previous);
    }

    fn declareVariable(self: *Parser) void {
        if (self.compiler.scope_depth == 0) {
            return;
        }

        const name = self.previous;

        var idx: usize = 0;
        while (idx < self.compiler.local_count) : (idx += 1) {
            const local = self.compiler.locals[idx];
            if (local.depth != -1 and local.depth < self.compiler.scope_depth) {
                break;
            }

            if (identifiersEqual(name, local.name)) {
                self.emitError("Already a variable with this name in this scope.");
            }
        }

        self.compiler.addLocal(name) catch |err| switch (err) {
            Compiler.Error.TooManyVariables => self.emitError("Too many local variables in function."),
        };
    }

    fn identifiersEqual(this: Token, that: Token) bool {
        if (this.length != that.length) {
            return false;
        }

        return std.mem.eql(u8, this.start[0..this.length], that.start[0..that.length]);
    }

    fn identifierConstant(self: *Parser, name: Token) u8 {
        return self.makeConstant(.{ .OBJ = Obj.copyString(self.alloc, name.start[0..name.length], self.vm) });
    }

    fn resolveLocal(self: *Parser, name: Token) i9 {
        var idx: usize = 0;
        while (idx < self.compiler.local_count) : (idx += 1) {
            const local = self.compiler.locals[idx];
            if (identifiersEqual(name, local.name)) {
                if (local.depth == -1) {
                    self.emitError("Can't read local variable in its own initializer.");
                }
                return @intCast(idx);
            }
        }

        return -1;
    }

    fn defineVariable(self: *Parser, global: u8) void {
        if (self.compiler.scope_depth > 0) {
            self.markInitialized();
            return;
        }
        self.emitBytes(.{ .OPCODE = .DEFINE_GLOBAL }, .{ .RAW = global });
    }

    fn markInitialized(self: *Parser) void {
        self.compiler.locals[self.compiler.local_count - 1].depth = self.compiler.scope_depth;
    }

    fn getRule(token_type: TokenType) ParseRule {
        return rules.get(@tagName(token_type)).?;
    }

    fn grouping(self: *Parser, _: ParseArguments) void {
        self.expression();
        self.consume(.RIGHT_PAREN, "Expect ')' after expression.");
    }

    fn beginScope(self: *Parser) void {
        self.compiler.scope_depth += 1;
    }

    fn endScope(self: *Parser) void {
        self.compiler.scope_depth -= 1;

        while (self.compiler.local_count > 0 and self.compiler.locals[self.compiler.local_count - 1].depth > self.compiler.scope_depth) {
            self.emitByte(.{ .OPCODE = .POP });
            self.compiler.local_count += 1;
        }
    }

    fn emitByte(self: *Parser, emitting_byte: EmittingByte) void {
        switch (emitting_byte) {
            .OPCODE => |opcode| self.currentChunk().write(false, opcode, self.previous.line),
            .RAW => |byte| self.currentChunk().write(true, byte, self.previous.line),
        }
    }

    fn emitBytes(self: *Parser, byte1: EmittingByte, byte2: EmittingByte) void {
        self.emitByte(byte1);
        self.emitByte(byte2);
    }

    fn emitJump(self: *Parser, instruction: EmittingByte) usize {
        self.emitByte(instruction);
        self.emitByte(.{ .RAW = 0xff });
        self.emitByte(.{ .RAW = 0xff });
        return self.currentChunk().count - 2;
    }

    fn patchJump(self: *Parser, offset: usize) void {
        const jump = self.currentChunk().count - offset - 2;

        if (jump > std.math.maxInt(u16)) {
            self.emitError("Too much code to jump over.");
        }

        self.currentChunk().code[offset] = @intCast((jump >> 8) & 0xff);
        self.currentChunk().code[offset + 1] = @intCast(jump & 0xff);
    }

    fn emitReturn(self: *Parser) void {
        self.emitByte(.{ .OPCODE = .RETURN });
    }

    fn makeConstant(self: *Parser, value: Value) u8 {
        const constant = self.currentChunk().addConstant(value);
        if (constant > std.math.maxInt(u8)) {
            self.emitError("Too many constants in one chunk.");
            return 0;
        }

        return @intCast(constant);
    }

    fn emitConstant(self: *Parser, value: Value) void {
        const constant = self.makeConstant(value);
        self.emitBytes(.{ .OPCODE = .CONSTANT }, .{ .RAW = constant });
    }

    fn currentChunk(self: *Parser) *Chunk {
        return self.compiling_chunk;
    }

    fn previousLexeme(self: *Parser) []const u8 {
        return self.previous.start[0..self.previous.length];
    }
    fn currentLexeme(self: *Parser) []const u8 {
        return self.current.start[0..self.current.length];
    }

    fn emitErrorAtCurrent(self: *Parser, msg: []const u8) void {
        self.emitErrorAt(self.current, msg) catch {
            std.debug.print("Could not print error\n", .{});
        };
    }

    fn emitError(self: *Parser, msg: []const u8) void {
        self.emitErrorAt(self.previous, msg) catch {
            std.debug.print("Could not print error\n", .{});
        };
    }

    fn emitErrorAt(self: *Parser, token: Token, msg: []const u8) !void {
        if (self.panic_mode) {
            return;
        }
        self.panic_mode = true;
        try StdErr.writer().print("[line {d}] Error", .{token.line});

        switch (token.token_type) {
            .EOF => try StdErr.writer().writeAll(" at end"),
            .ERROR => {},
            else => try StdErr.writer().print(" at '{s}'", .{token.start[0..token.length]}),
        }

        try StdErr.writer().print(": {s}\n", .{msg});
        self.had_error = true;
    }

    fn synchronize(self: *Parser) void {
        self.panic_mode = false;

        while (self.current.token_type != .EOF) {
            if (self.previous.token_type == .SEMICOLON) {
                return;
            }

            switch (self.current.token_type) {
                .CLASS, .FUN, .VAR, .FOR, .IF, .WHILE, .PRINT, .RETURN => return,
                else => {},
            }
            self.advance();
        }
    }
};

const Compiler = struct {
    locals: [LOCAL_COUNT]Local = .{undefined} ** LOCAL_COUNT,
    local_count: usize = 0,
    scope_depth: isize = 0,

    const Error = error{
        TooManyVariables,
    };

    const Local = struct {
        name: Token,
        depth: isize,
    };

    fn addLocal(self: *Compiler, name: Token) !void {
        if (self.local_count == LOCAL_COUNT) {
            return Compiler.Error.TooManyVariables;
        }
        const local = &self.locals[self.local_count + 1];
        self.local_count += 1;
        local.* = .{
            .name = name,
            .depth = -1,
        };
    }
};

pub fn compile(alloc: Allocator, vm: *VM, source: []const u8, chunk: *Chunk) Error!void {
    var compiler: Compiler = .{};
    const scanner = Scanner.init(source);
    var parser: Parser = .{
        .current = undefined,
        .previous = undefined,
        .scanner = scanner,
        .compiling_chunk = chunk,
        .alloc = alloc,
        .vm = vm,
        .compiler = &compiler,
    };

    parser.advance();
    while (!parser.match(.EOF)) {
        parser.declaration();
    }
    endCompiler(&parser);

    if (parser.had_error) {
        return Error.ParserError;
    }
}

fn endCompiler(parser: *Parser) void {
    parser.emitReturn();

    if (comptime DEBUG_PRINT_CODE) {
        @import("debug.zig").disassembleChunk(parser.currentChunk(), "code");
    }
}
