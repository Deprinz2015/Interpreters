<?php

namespace Nkoll\Plox\Lox;

use Nkoll\Plox\PloxCommand;
use Nkoll\Plox\Lox\Error\ParserError;
use Nkoll\Plox\Lox\Expr\BinaryExpr;
use Nkoll\Plox\Lox\Expr\Expr;
use Nkoll\Plox\Lox\Expr\GroupingExpr;
use Nkoll\Plox\Lox\Expr\LiteralExpr;
use Nkoll\Plox\Lox\Expr\UnaryExpr;
use Nkoll\Plox\Lox\Stmt\ExpressionStmt;
use Nkoll\Plox\Lox\Stmt\PrintStmt;
use Nkoll\Plox\Lox\Stmt\Stmt;

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
            while(!$this->isAtEnd()) {
                $stmts[] = $this->statement();
            }
            return $stmts;
        } catch (ParserError) {
            return null;
        }
    }

    private function statement(): Stmt
    {
        if($this->match(TokenType::PRINT)) {
            return $this->printStatement();
        }

        return $this->expressionStatement();
    }

    private function printStatement(): Stmt
    {
        $expr = $this->expression();
        $this->consume(TokenType::SEMICOLON, "Expect ';' after value.");
        return new PrintStmt($expr);
    }

    private function expressionStatement(): Stmt
    {
        $expr = $this->expression();
        $this->consume(TokenType::SEMICOLON, "Expect ';' after expression.");
        return new ExpressionStmt($expr);
    }

    private function expression(): Expr
    {
        return $this->equality();
    }

    private function equality(): Expr
    {
        $expr = $this->comparison();

        while($this->match(TokenType::BANG_EQUAL, TokenType::EQUAL_EQUAL)) {
            $op = $this->previous();
            $right = $this->comparison();
            $expr = new BinaryExpr($expr, $op, $right);
        }

        return $expr;
    }

    private function comparison(): Expr
    {
        $expr = $this->term();

        while($this->match(TokenType::GREATER, TokenType::GREATER_EQUAL, TokenType::LESS, TokenType::LESS_EQUAL)) {
            $op = $this->previous();
            $right = $this->term();
            $expr = new BinaryExpr($expr, $op, $right);
        }

        return $expr;
    }

    private function term(): Expr
    {
        $expr = $this->factor();

        while($this->match(TokenType::PLUS, TokenType::MINUS)) {
            $op = $this->previous();
            $right = $this->factor();
            $expr = new BinaryExpr($expr, $op, $right);
        }

        return $expr;
    }

    private function factor(): Expr
    {
        $expr = $this->unary();

        while($this->match(TokenType::STAR, TokenType::SLASH)) {
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

        return $this->primary();
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

        if ($this->match(TokenType::LEFT_PAREN)) {
            $expr = $this->expression();
            $this->consume(TokenType::RIGHT_PAREN, "Expect ')' after expression.");
            return new GroupingExpr($expr);
        }

        throw $this->error($this->peek(), "Expect expression.");
    }

    private function match(TokenType... $types): bool
    {
        foreach($types as $type) {
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
            $this->current++;
        }

        return $this->previous();
    }

    private function isAtEnd(): bool
    {
        return $this->peek()->type === TokenType::EOF;
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

        while(!$this->isAtEnd()) {
            if ($this->previous()->type === TokenType::SEMICOLON) {
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
