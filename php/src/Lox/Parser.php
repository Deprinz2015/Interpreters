<?php

namespace Nkoll\Plox\Lox;

use Nkoll\Plox\Lox\Error\ParserError;
use Nkoll\Plox\Lox\Expr\AssignExpr;
use Nkoll\Plox\Lox\Expr\BinaryExpr;
use Nkoll\Plox\Lox\Expr\CallExpr;
use Nkoll\Plox\Lox\Expr\Expr;
use Nkoll\Plox\Lox\Expr\GroupingExpr;
use Nkoll\Plox\Lox\Expr\LiteralExpr;
use Nkoll\Plox\Lox\Expr\LogicalExpr;
use Nkoll\Plox\Lox\Expr\UnaryExpr;
use Nkoll\Plox\Lox\Expr\VariableExpr;
use Nkoll\Plox\Lox\Stmt\BlockStmt;
use Nkoll\Plox\Lox\Stmt\ExpressionStmt;
use Nkoll\Plox\Lox\Stmt\FunctionStmt;
use Nkoll\Plox\Lox\Stmt\IfStmt;
use Nkoll\Plox\Lox\Stmt\PrintStmt;
use Nkoll\Plox\Lox\Stmt\ReturnStmt;
use Nkoll\Plox\Lox\Stmt\Stmt;
use Nkoll\Plox\Lox\Stmt\VarStmt;
use Nkoll\Plox\Lox\Stmt\WhileStmt;
use Nkoll\Plox\PloxCommand;

class Parser
{
    private array $tokens;
    private int $current = 0;

    public function __construct(array $tokens)
    {
        $this->tokens = $tokens;
    }

    /** @return ?Stmt[]  */
    public function parse(): ?array
    {
        try {
            $stmts = [];
            while (!$this->isAtEnd()) {
                $stmts[] = $this->declaration();
            }

            return $stmts;
        } catch (ParserError) {
            return null;
        }
    }

    private function declaration(): ?Stmt
    {
        try {
            if ($this->match(TokenType::FUN)) {
                return $this->function('function');
            }
            if ($this->match(TokenType::VAR)) {
                return $this->varDeclaration();
            }

            return $this->statement();
        } catch (ParserError) {
            $this->synchronize();

            return null;
        }
    }

    private function varDeclaration(): Stmt
    {
        $name = $this->consume(TokenType::IDENTIFIER, 'Expect variable name.');

        $initializer = null;
        if ($this->match(TokenType::EQUAL)) {
            $initializer = $this->expression();
        }

        $this->consume(TokenType::SEMICOLON, "Expect ';' after variable declaration.");

        return new VarStmt($name, $initializer);
    }

    private function statement(): Stmt
    {
        if ($this->match(TokenType::IF)) {
            return $this->ifStatement();
        }

        if ($this->match(TokenType::WHILE)) {
            return $this->whileStatement();
        }

        if ($this->match(TokenType::FOR)) {
            return $this->forStatement();
        }

        if ($this->match(TokenType::PRINT)) {
            return $this->printStatement();
        }

        if ($this->match(TokenType::RETURN)) {
            return $this->returnStatement();
        }

        if ($this->match(TokenType::LEFT_BRACE)) {
            return new BlockStmt($this->block());
        }

        return $this->expressionStatement();
    }

    private function ifStatement(): Stmt
    {
        $this->consume(TokenType::LEFT_PAREN, "Expect '(' after 'if'.");
        $condition = $this->expression();
        $this->consume(TokenType::RIGHT_PAREN, "Expect ')' after condition.");

        $thenBranch = $this->statement();
        $elseBranch = null;
        if ($this->match(TokenType::ELSE)) {
            $elseBranch = $this->statement();
        }

        return new IfStmt($condition, $thenBranch, $elseBranch);
    }

    private function whileStatement(): Stmt
    {
        $this->consume(TokenType::LEFT_PAREN, "Expect '(' after 'while'.");
        $condition = $this->expression();
        $this->consume(TokenType::RIGHT_PAREN, "Expect ')' after condition.");
        $body = $this->statement();

        return new WhileStmt($condition, $body);
    }

    private function forStatement(): Stmt
    {
        $this->consume(TokenType::LEFT_PAREN, "Expect '(' after 'for'.");

        $initializer = null;
        if ($this->match(TokenType::SEMICOLON)) {
            $initializer = null; // skipped
        } elseif ($this->match(TokenType::VAR)) {
            $initializer = $this->varDeclaration();
        } else {
            $initializer = $this->expressionStatement();
        }

        $condition = null;
        if (!$this->check(TokenType::SEMICOLON)) {
            $condition = $this->expression();
        }
        $this->consume(TokenType::SEMICOLON, "Expect ';' after loop condition.");

        $increment = null;
        if (!$this->check(TokenType::RIGHT_PAREN)) {
            $increment = $this->expression();
        }
        $this->consume(TokenType::RIGHT_PAREN, "Expect ')' after for clauses.");
        $body = $this->statement();

        if ($increment) {
            $body = new BlockStmt([$body, new ExpressionStmt($increment)]);
        }

        if (!$condition) {
            $condition = new LiteralExpr(true);
        }
        $body = new WhileStmt($condition, $body);

        if ($initializer) {
            $body = new BlockStmt([$initializer, $body]);
        }

        return $body;
    }

    private function printStatement(): Stmt
    {
        $expr = $this->expression();
        $this->consume(TokenType::SEMICOLON, "Expect ';' after value.");

        return new PrintStmt($expr);
    }

    private function returnStatement(): Stmt {
        $keyword = $this->previous();

        $value = null;
        if (!$this->check(TokenType::SEMICOLON)) {
            $value = $this->expression();
        }

        $this->consume(TokenType::SEMICOLON, "Expected ';' after return value.");
        return new ReturnStmt($keyword, $value);
    }

    private function expressionStatement(): Stmt
    {
        $expr = $this->expression();
        $this->consume(TokenType::SEMICOLON, "Expect ';' after expression.");

        return new ExpressionStmt($expr);
    }

    private function function(string $kind): Stmt
    {
        $name = $this->consume(TokenType::IDENTIFIER, "Expect $kind name.");
        $this->consume(TokenType::LEFT_PAREN, "Expect '(' after $kind name.");
        $params = [];
        if (!$this->check(TokenType::RIGHT_PAREN)) {
            do {
                if (count($params) >= 255) {
                    $this->error($this->peek(), "Can't have more than 255 parameters.");
                }

                $params[] = $this->consume(TokenType::IDENTIFIER, 'Expect parameter name.');
            } while ($this->match(TokenType::COMMA));
        }

        $this->consume(TokenType::RIGHT_PAREN, "Expect ')' after parameters.");

        $this->consume(TokenType::LEFT_BRACE, "Expect '{' before $kind body.");
        $body = $this->block();

        return new FunctionStmt($name, $params, $body);
    }

    /** @return Stmt[]  */
    private function block(): array
    {
        $stmts = [];

        while (!$this->check(TokenType::RIGHT_BRACE) && !$this->isAtEnd()) {
            $stmts[] = $this->declaration();
        }

        $this->consume(TokenType::RIGHT_BRACE, "Expect '}' after block.");

        return $stmts;
    }

    private function expression(): Expr
    {
        return $this->assignment();
    }

    private function assignment(): Expr
    {
        $expr = $this->or();

        if ($this->match(TokenType::EQUAL)) {
            $equals = $this->previous();
            $value = $this->assignment();

            if ($expr instanceof VariableExpr) {
                $name = $expr->name;

                return new AssignExpr($name, $value);
            }

            $this->error($equals, 'Invalid assignment target.');
        }

        return $expr;
    }

    private function or(): Expr
    {
        $expr = $this->and();

        while ($this->match(TokenType::OR)) {
            $op = $this->previous();
            $right = $this->and();
            $expr = new LogicalExpr($expr, $op, $right);
        }

        return $expr;
    }

    private function and(): Expr
    {
        $expr = $this->equality();

        while ($this->match(TokenType::AND)) {
            $op = $this->previous();
            $right = $this->equality();
            $expr = new LogicalExpr($expr, $op, $right);
        }

        return $expr;
    }

    private function equality(): Expr
    {
        $expr = $this->comparison();

        while ($this->match(TokenType::BANG_EQUAL, TokenType::EQUAL_EQUAL)) {
            $op = $this->previous();
            $right = $this->comparison();
            $expr = new BinaryExpr($expr, $op, $right);
        }

        return $expr;
    }

    private function comparison(): Expr
    {
        $expr = $this->term();

        while ($this->match(TokenType::GREATER, TokenType::GREATER_EQUAL, TokenType::LESS, TokenType::LESS_EQUAL)) {
            $op = $this->previous();
            $right = $this->term();
            $expr = new BinaryExpr($expr, $op, $right);
        }

        return $expr;
    }

    private function term(): Expr
    {
        $expr = $this->factor();

        while ($this->match(TokenType::PLUS, TokenType::MINUS)) {
            $op = $this->previous();
            $right = $this->factor();
            $expr = new BinaryExpr($expr, $op, $right);
        }

        return $expr;
    }

    private function factor(): Expr
    {
        $expr = $this->unary();

        while ($this->match(TokenType::STAR, TokenType::SLASH)) {
            $op = $this->previous();
            $right = $this->unary();
            $expr = new BinaryExpr($expr, $op, $right);
        }

        return $expr;
    }

    private function unary(): Expr
    {
        if ($this->match(TokenType::BANG, TokenType::MINUS)) {
            return new UnaryExpr($this->previous(), $this->unary());
        }

        return $this->call();
    }

    private function finishCall(Expr $callee): Expr
    {
        $args = [];

        if (!$this->check(TokenType::RIGHT_PAREN)) {
            do {
                if (count($args) >= 255) {
                    $this->error($this->peek(), "Can't have more than 255 arguments.");
                }
                $args[] = $this->expression();
            } while ($this->match(TokenType::COMMA));
        }

        $paren = $this->consume(TokenType::RIGHT_PAREN, "Expect ')' after arguments.");

        return new CallExpr($callee, $paren, $args);
    }

    private function call(): Expr
    {
        $expr = $this->primary();

        while (true) {
            if ($this->match(TokenType::LEFT_PAREN)) {
                $expr = $this->finishCall($expr);
            } else {
                break;
            }
        }

        return $expr;
    }

    private function primary(): Expr
    {
        if ($this->match(TokenType::FALSE)) {
            return new LiteralExpr(false);
        }
        if ($this->match(TokenType::TRUE)) {
            return new LiteralExpr(true);
        }
        if ($this->match(TokenType::NIL)) {
            return new LiteralExpr(null);
        }

        if ($this->match(TokenType::NUMBER, TokenType::STRING)) {
            return new LiteralExpr($this->previous()->literal);
        }

        if ($this->match(TokenType::IDENTIFIER)) {
            return new VariableExpr($this->previous());
        }

        if ($this->match(TokenType::LEFT_PAREN)) {
            $expr = $this->expression();
            $this->consume(TokenType::RIGHT_PAREN, "Expect ')' after expression.");

            return new GroupingExpr($expr);
        }

        throw $this->error($this->peek(), 'Expect expression.');
    }

    private function match(TokenType ...$types): bool
    {
        foreach ($types as $type) {
            if ($this->check($type)) {
                $this->advance();

                return true;
            }
        }

        return false;
    }

    private function consume(TokenType $type, string $msg): Token
    {
        if ($this->check($type)) {
            return $this->advance();
        }

        throw $this->error($this->peek(), $msg);
    }

    private function check(TokenType $type): bool
    {
        if ($this->isAtEnd()) {
            return false;
        }

        return $this->peek()->type === $type;
    }

    private function advance(): Token
    {
        if (!$this->isAtEnd()) {
            ++$this->current;
        }

        return $this->previous();
    }

    private function isAtEnd(): bool
    {
        return TokenType::EOF === $this->peek()->type;
    }

    private function peek(): Token
    {
        return $this->tokens[$this->current];
    }

    private function previous(): Token
    {
        return $this->tokens[$this->current - 1];
    }

    private function error(Token $token, string $msg): ParserError
    {
        PloxCommand::errorToken($token, $msg);

        return new ParserError();
    }

    private function synchronize()
    {
        $this->advance();

        while (!$this->isAtEnd()) {
            if (TokenType::SEMICOLON === $this->previous()->type) {
                return;
            }

            switch ($this->peek()->type) {
                case TokenType::CLASS_KEYWORD:
                case TokenType::FUN:
                case TokenType::VAR:
                case TokenType::FOR:
                case TokenType::IF:
                case TokenType::WHILE:
                case TokenType::PRINT:
                case TokenType::RETURN:
                    return;
            }

            $this->advance();
        }
    }
}
