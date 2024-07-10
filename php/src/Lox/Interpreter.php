<?php

namespace Nkoll\Plox\Lox;

use Nkoll\Plox\Lox\Error\RuntimeError;
use Nkoll\Plox\PloxCommand;

class Interpreter implements Visitor
{
    public function interpret(Expr $expr): void {
        try {
            $value = $this->evaluate($expr);
            echo $this->stringify($value) . PHP_EOL;
        } catch (RuntimeError $e) {
            PloxCommand::runtimeError($e);
        }
    }

    private function stringify($value): string {
        if ($value === null) {
            return 'nil';
        }

        if (is_float($value)) {
            $text = "$value";
            if (str_ends_with($text, ".0")) {
                $text = substr($text, 0, strlen($text) - 2);
            }
            return $text;
        }

        if (is_bool($value)) {
            return $value ? "true" : "false";
        }

        return "$value";
    }

    private function evaluate(Expr $expr)
    {
        return $expr->accept($this);
    }

    public function visitBinaryExpr(BinaryExpr $expr)
    {
        $left = $this->evaluate($expr->left);
        $right = $this->evaluate($expr->right);

        switch ($expr->operator->type) {
            case TokenType::GREATER:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left > (float)$right;
            case TokenType::GREATER_EQUAL:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left >= (float)$right;
            case TokenType::LESS:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left < (float)$right;
            case TokenType::LESS_EQUAL:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left <= (float)$right;
            case TokenType::EQUAL_EQUAL:
                return $left === $right;
            case TokenType::BANG_EQUAL:
                return $left !== $right;

            case TokenType::MINUS:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left - (float)$right;

            case TokenType::PLUS:
                if (is_double($left) && is_double($right)) {
                    return $left + $right;
                }

                if (is_string($left) && is_string($right)) {
                    return "$left$right";
                }

                throw new RuntimeError($expr->operator, "Operands must be two numbers or two string.");
                break;

            case TokenType::SLASH:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left / (float)$right;

            case TokenType::STAR:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left * (float)$right;
        }
    }

    public function visitGroupingExpr(GroupingExpr $expr)
    {
        return $this->evaluate($expr->expression);
    }

    public function visitLiteralExpr(LiteralExpr $expr)
    {
        return $expr->value;
    }

    public function visitUnaryExpr(UnaryExpr $expr)
    {
        $right = $this->evaluate($expr->right);

        switch ($expr->operator->type) {
            case TokenType::MINUS:
                $this->checkNumberOperand($expr->operator, $right);
                return -(float)$right;
            case TokenType::BANG:
                return !$right;
        }

        return null;
    }

    private function checkNumberOperand(Token $op, $operand): void
    {
        if (is_float($operand)) {
            return;
        }

        throw new RuntimeError($op, "Operand must be a number.");
    }

    private function checkNumberOperands(Token $op, $left, $right): void {
        if (is_float($left) && is_float($right)) {
            return;
        }

        throw new RuntimeError($op, "Operands must be a number.");
    }

}
