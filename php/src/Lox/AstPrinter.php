<?php

namespace Nkoll\Plox\Lox;

class AstPrinter implements Visitor
{

    public function visitBinaryExpr(BinaryExpr $expr) { 
        return $this->parenthesize($expr->operator->lexeme, $expr->left, $expr->right);
    }

    public function visitGroupingExpr(GroupingExpr $expr) {
        return $this->parenthesize('group', $expr->expression);
    }

    public function visitLiteralExpr(LiteralExpr $expr) {
        if ($expr->value === null) {
            return "nil";
        }

        return "{$expr->value}";
    }

    public function visitUnaryExpr(UnaryExpr $expr) {
        return $this->parenthesize($expr->operator->lexeme, $expr->right);
    }

    private function parenthesize(string $name, Expr... $exprs){
        $exprs = array_map(function (Expr $expr) {
            return $expr->accept($this);
        }, $exprs);
        $values = implode(" ", $exprs);
        return "($name $values)";
    }

    public function print(Expr $expr): string {
        return $expr->accept($this);
    }
}
