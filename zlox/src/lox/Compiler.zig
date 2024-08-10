const DEBUG_PRINT_CODE = @import("config").chunk_trace;
const LOCAL_COUNT = 256;
const UPVALUE_COUNT = 256;

const std = @import("std");
const Allocator = std.mem.Allocator;
const StdOut = std.io.getStdOut();
const StdErr = std.io.getStdErr();

const GC = @import("GC.zig");
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
        .{ @tagName(TokenType.LEFT_PAREN), .{ .prefix = grouping, .infix = call, .precedence = .CALL } },
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
        .{ @tagName(TokenType.AND), .{ .prefix = null, .infix = and_, .precedence = .AND } },
        .{ @tagName(TokenType.CLASS), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.ELSE), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.FALSE), .{ .prefix = literal, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.FOR), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.FUN), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.IF), .{ .prefix = null, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.NIL), .{ .prefix = literal, .infix = null, .precedence = .NONE } },
        .{ @tagName(TokenType.OR), .{ .prefix = null, .infix = or_, .precedence = .OR } },
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
        if (self.match(.FUN)) {
            self.funDeclaration();
        } else if (self.match(.VAR)) {
            self.varDeclaration();
        } else {
            self.statement();
        }

        if (self.panic_mode) {
            self.synchronize();
        }
    }

    fn funDeclaration(self: *Parser) void {
        const global = self.parseVariable("Expect function name.");
        self.markInitialized();
        self.function(.FUNCTION);
        self.defineVariable(global);
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
        if (self.match(.LEFT_BRACE)) {
            self.beginScope();
            self.block();
            self.endScope();
        } else if (self.match(.IF)) {
            self.ifStatement();
        } else if (self.match(.RETURN)) {
            self.returnStatement();
        } else if (self.match(.WHILE)) {
            self.whileStatement();
        } else if (self.match(.FOR)) {
            self.forStatement();
        } else {
            self.expressionStatement();
        }
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

    fn returnStatement(self: *Parser) void {
        if (self.compiler.fun_type == .SCRIPT) {
            self.emitError("Can't return from top-level code.");
        }

        if (self.match(.SEMICOLON)) {
            self.emitReturn();
            return;
        }

        self.expression();
        self.consume(.SEMICOLON, "Expect ';' after return value;");
        self.emitByte(.{ .OPCODE = .RETURN });
    }

    fn whileStatement(self: *Parser) void {
        const loop_start = self.currentChunk().count;
        self.consume(.LEFT_PAREN, "Expect '(' after 'while'.");
        self.expression();
        self.consume(.RIGHT_PAREN, "Expect ')' after condition.");

        const exitJump = self.emitJump(.{ .OPCODE = .JUMP_IF_FALSE });
        self.emitByte(.{ .OPCODE = .POP });
        self.statement();
        self.emitLoop(loop_start);

        self.patchJump(exitJump);
        self.emitByte(.{ .OPCODE = .POP });
    }

    fn forStatement(self: *Parser) void {
        self.beginScope();
        self.consume(.LEFT_PAREN, "Expect '(' after 'for'.");
        if (self.match(.SEMICOLON)) {
            // noop
        } else if (self.match(.VAR)) {
            self.varDeclaration();
        } else {
            self.expressionStatement();
        }

        var loop_start = self.currentChunk().count;

        var has_condition = false;
        const exit_jump = jump: {
            if (self.match(.SEMICOLON)) {
                break :jump 0;
            }

            self.expression();
            self.consume(.SEMICOLON, "Expect ';' after loop condition.");

            const jump = self.emitJump(.{ .OPCODE = .JUMP_IF_FALSE });
            self.emitByte(.{ .OPCODE = .POP });
            has_condition = true;
            break :jump jump;
        };

        if (!self.match(.RIGHT_PAREN)) {
            const body_jump = self.emitJump(.{ .OPCODE = .JUMP });
            const inc_start = self.currentChunk().count;

            self.expression();
            self.emitByte(.{ .OPCODE = .POP });
            self.consume(.RIGHT_PAREN, "Expect ')' after for clauses.");

            self.emitLoop(loop_start);
            loop_start = inc_start;
            self.patchJump(body_jump);
        }

        self.statement();
        self.emitLoop(loop_start);

        if (has_condition) {
            self.patchJump(exit_jump);
            self.emitByte(.{ .OPCODE = .POP });
        }

        self.endScope();
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

        self.emitConstant(self.stringValue(previous[1 .. previous.len - 1]));
    }

    fn variable(self: *Parser, arguments: ParseArguments) void {
        self.namedVariables(self.previous, arguments.can_assign);
    }

    fn function(self: *Parser, fun_type: Compiler.FunctionType) void {
        var compiler = Compiler.init(self.alloc, fun_type, self.compiler, self.vm);
        self.compiler = &compiler;
        self.vm.gc.compiler = &compiler;
        self.compiler.function.name = Obj.String.copy(self.alloc, self.previousLexeme(), self.vm);
        self.beginScope();

        self.consume(.LEFT_PAREN, "Expect '(' after function name.");
        if (!self.check(.RIGHT_PAREN)) {
            self.compiler.function.arity += 1;
            var constant = self.parseVariable("Expect parameter name.");
            self.defineVariable(constant);
            while (self.match(.COMMA)) {
                self.compiler.function.arity += 1;
                if (self.compiler.function.arity > 255) {
                    self.emitErrorAtCurrent("Can't have more than 255 parameters.");
                }
                constant = self.parseVariable("Expect parameter name.");
                self.defineVariable(constant);
            }
        }
        self.consume(.RIGHT_PAREN, "Expect ')' after parameters.");
        self.consume(.LEFT_BRACE, "Expect '{' before function body.");
        self.block();

        const function_obj = compiler.endCompiler(self);
        self.emitBytes(.{ .OPCODE = .CLOSURE }, .{ .RAW = self.makeConstant(.{ .OBJ = &function_obj.obj }) });

        for (compiler.upvalues, 0..) |upvalue, i| {
            if (i >= function_obj.upvalue_count) {
                break;
            }

            self.emitByte(.{ .RAW = if (upvalue.is_local) 1 else 0 });
            self.emitByte(.{ .RAW = upvalue.index });
        }
    }

    fn namedVariables(self: *Parser, name: Token, can_assign: bool) void {
        var local = false;
        var upvalue = false;
        const arg: u8 = arg: {
            if (self.resolveLocal(self.compiler, name)) |idx| {
                local = true;
                break :arg idx;
            }

            if (self.resolveUpvalue(self.compiler, name)) |idx| {
                upvalue = true;
                break :arg idx;
            }

            break :arg self.identifierConstant(name);
        };

        const getOp: Chunk.OpCode = if (local) .GET_LOCAL else if (upvalue) .GET_UPVALUE else .GET_GLOBAL;
        const setOp: Chunk.OpCode = if (local) .SET_LOCAL else if (upvalue) .SET_UPVALUE else .SET_GLOBAL;

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
                infix(self, .{ .can_assign = can_assign });
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
        const chars = name.start[0..name.length];
        return self.makeConstant(self.stringValue(chars));
    }

    fn resolveLocal(self: *Parser, compiler: *Compiler, name: Token) ?u8 {
        var idx: usize = 0;
        while (idx < compiler.local_count) : (idx += 1) {
            const local = compiler.locals[idx];
            if (identifiersEqual(name, local.name)) {
                if (local.depth == -1) {
                    self.emitError("Can't read local variable in its own initializer.");
                }
                return @intCast(idx);
            }
        }

        return null;
    }

    fn resolveUpvalue(self: *Parser, compiler: *Compiler, name: Token) ?u8 {
        if (compiler.enclosing == null) {
            return null;
        }

        if (self.resolveLocal(compiler.enclosing.?, name)) |idx| {
            compiler.enclosing.?.locals[idx].is_captured = true;
            return compiler.addUpvalue(idx, true) catch |err| switch (err) {
                Compiler.Error.TooManyVariables => {
                    self.emitError("Too many closure variables in function.");
                    return null;
                },
            };
        }

        if (self.resolveUpvalue(compiler.enclosing.?, name)) |idx| {
            return compiler.addUpvalue(idx, false) catch |err| switch (err) {
                Compiler.Error.TooManyVariables => {
                    self.emitError("Too many closure variables in function.");
                    return null;
                },
            };
        }

        return null;
    }

    fn defineVariable(self: *Parser, global: u8) void {
        if (self.compiler.scope_depth > 0) {
            self.markInitialized();
            return;
        }
        self.emitBytes(.{ .OPCODE = .DEFINE_GLOBAL }, .{ .RAW = global });
    }

    fn and_(self: *Parser, _: ParseArguments) void {
        const endJump = self.emitJump(.{ .OPCODE = .JUMP_IF_FALSE });

        self.emitByte(.{ .OPCODE = .POP });
        self.parsePrecedence(.AND);

        self.patchJump(endJump);
    }

    fn or_(self: *Parser, _: ParseArguments) void {
        const elseJump = self.emitJump(.{ .OPCODE = .JUMP_IF_FALSE });
        const endJump = self.emitJump(.{ .OPCODE = .JUMP });

        self.patchJump(elseJump);
        self.emitByte(.{ .OPCODE = .POP });

        self.parsePrecedence(.OR);
        self.patchJump(endJump);
    }

    fn markInitialized(self: *Parser) void {
        if (self.compiler.scope_depth == 0) {
            return;
        }
        self.compiler.locals[self.compiler.local_count - 1].depth = self.compiler.scope_depth;
    }

    fn getRule(token_type: TokenType) ParseRule {
        return rules.get(@tagName(token_type)).?;
    }

    fn call(self: *Parser, _: ParseArguments) void {
        const arg_count = self.argumentList();
        self.emitBytes(.{ .OPCODE = .CALL }, .{ .RAW = arg_count });
    }

    fn argumentList(self: *Parser) u8 {
        var arg_count: u16 = 0;
        if (!self.check(.RIGHT_PAREN)) {
            self.expression();
            arg_count += 1;
            while (self.match(.COMMA)) {
                self.expression();
                if (arg_count == 255) {
                    self.emitError("Can't have more than 255 arguments.");
                }
                arg_count += 1;
            }
        }
        self.consume(.RIGHT_PAREN, "Expect ')' after arguments.");
        if (arg_count > 255) {
            return 255;
        }
        return @intCast(arg_count);
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
            if (self.compiler.locals[self.compiler.local_count - 1].is_captured) {
                self.emitByte(.{ .OPCODE = .CLOSE_UPVALUE });
            } else {
                self.emitByte(.{ .OPCODE = .POP });
            }
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

    fn emitLoop(self: *Parser, loop_start: usize) void {
        self.emitByte(.{ .OPCODE = .LOOP });

        const offset = self.currentChunk().count - loop_start + 2;
        if (offset > std.math.maxInt(u16)) {
            self.emitError("Loop body to large.");
        }

        self.emitByte(.{ .RAW = @intCast((offset >> 8) & 0xff) });
        self.emitByte(.{ .RAW = @intCast(offset & 0xff) });
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
        self.emitByte(.{ .OPCODE = .NIL });
        self.emitByte(.{ .OPCODE = .RETURN });
    }

    fn makeConstant(self: *Parser, value: Value) u8 {
        const constant = self.currentChunk().addConstant(value, self.vm);
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
        return &self.compiler.function.chunk;
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

    fn stringValue(self: *Parser, chars: []const u8) Value {
        const str = Obj.String.copy(self.alloc, chars, self.vm);
        return .{ .OBJ = &str.obj };
    }
};

pub const Compiler = struct {
    enclosing: ?*Compiler,
    function: *Obj.Function,
    fun_type: FunctionType,
    locals: [LOCAL_COUNT]Local = .{undefined} ** LOCAL_COUNT,
    upvalues: [UPVALUE_COUNT]Upvalue = .{undefined} ** UPVALUE_COUNT,
    local_count: usize = 0,
    scope_depth: isize = 0,

    const FunctionType = enum {
        FUNCTION,
        SCRIPT,
    };

    const Error = error{
        TooManyVariables,
    };

    const Local = struct {
        name: Token,
        depth: isize,
        is_captured: bool,
    };

    const Upvalue = struct {
        index: u8,
        is_local: bool,
    };

    fn init(alloc: Allocator, fun_type: FunctionType, enclosing: ?*Compiler, vm: *VM) Compiler {
        var compiler: Compiler = .{
            .enclosing = enclosing,
            .function = undefined,
            .fun_type = fun_type,
        };
        compiler.function = Obj.Function.create(alloc, vm);

        const local = &compiler.locals[compiler.local_count];
        compiler.local_count += 1;
        local.* = .{
            .depth = 0,
            .is_captured = false,
            .name = .{
                .token_type = .IDENTIFIER,
                .start = "",
                .length = 1,
                .line = 0,
            },
        };

        return compiler;
    }

    fn addLocal(self: *Compiler, name: Token) !void {
        if (self.local_count == LOCAL_COUNT) {
            return Compiler.Error.TooManyVariables;
        }
        const local = &self.locals[self.local_count];
        self.local_count += 1;
        local.* = .{
            .name = name,
            .depth = -1,
            .is_captured = false,
        };
    }

    fn addUpvalue(self: *Compiler, idx: u8, is_local: bool) !u8 {
        const upvalue_count = self.function.upvalue_count;

        for (self.upvalues, 0..) |upvalue, i| {
            if (i >= upvalue_count) {
                break;
            }

            if (upvalue.index == idx and upvalue.is_local == is_local) {
                return @intCast(i);
            }
        }

        if (upvalue_count == UPVALUE_COUNT) {
            return Compiler.Error.TooManyVariables;
        }

        self.upvalues[upvalue_count] = .{
            .is_local = is_local,
            .index = idx,
        };
        self.function.upvalue_count += 1;
        return @intCast(upvalue_count);
    }

    fn endCompiler(self: *Compiler, parser: *Parser) *Obj.Function {
        const function = self.function;
        parser.emitReturn();

        if (comptime DEBUG_PRINT_CODE) {
            if (function.name) |name| {
                @import("debug.zig").disassembleChunk(parser.currentChunk(), name.chars);
            } else {
                @import("debug.zig").disassembleChunk(parser.currentChunk(), "<script>");
            }
        }

        if (self.enclosing) |enclosing| {
            parser.compiler = enclosing;
            parser.vm.gc.compiler = enclosing;
        }
        return function;
    }

    pub fn markCompilerRoots(self: *Compiler, gc: *GC) void {
        var current: ?*Compiler = self;
        while (current) |compiler| {
            gc.markObject(&compiler.function.obj);
            current = compiler.enclosing;
        }
    }
};

pub fn compile(alloc: Allocator, vm: *VM, source: []const u8) Error!*Obj.Function {
    var compiler = Compiler.init(alloc, .SCRIPT, null, vm);
    vm.gc.compiler = &compiler;
    const scanner = Scanner.init(source);
    var parser: Parser = .{
        .current = undefined,
        .previous = undefined,
        .scanner = scanner,
        .alloc = alloc,
        .vm = vm,
        .compiler = &compiler,
    };

    parser.advance();
    while (!parser.match(.EOF)) {
        parser.declaration();
    }
    const function = compiler.endCompiler(&parser);

    if (parser.had_error) {
        return Error.ParserError;
    }

    return function;
}
