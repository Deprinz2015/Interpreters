<?php

namespace Nkoll\Plox\Lox\Expr;

interface ExprVisitor
{
    public function visitBinaryExpr(BinaryExpr $expr);
    public function visitGroupingExpr(GroupingExpr $expr);
    public function visitLiteralExpr(LiteralExpr $expr);
    public function visitUnaryExpr(UnaryExpr $expr);
    public function visitVariableExpr(VariableExpr $expr);
}