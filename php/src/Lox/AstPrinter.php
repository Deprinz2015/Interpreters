<?php

namespace Nkoll\Plox\Lox;

class AstPrinter implements Visitor
{

    public function visitBinaryExpr(Binary $expr) { 
        return $this->parenthesize($expr->operator->lexeme, $expr->left, $expr->right);
    }

    public function visitGroupingExpr(Grouping $expr) {
        return $this->parenthesize('group', $expr->expression);
    }

    public function visitLiteralExpr(Literal $expr) {
        if ($expr->value === null) {
            return "nil";
        }

        return "$expr";
    }

    public function visitUnaryExpr(Unary $expr) {
        return $this->parenthesize($expr->operator->lexeme, $expr->right);
    }

    private function parenthesize(string $name, Expr... $exprs){
        $exprs = array_map(function (Expr $expr) {
            return $expr->accept($this);
        }, $exprs);
        $values = implode(" ", $exprs);
        return "($name $values)";
    }
}
