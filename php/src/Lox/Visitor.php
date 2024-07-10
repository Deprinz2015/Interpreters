<?php

namespace Nkoll\Plox\Lox;

interface Visitor
{
    public function visitBinaryExpr(BinaryExpr $expr);
    public function visitGroupingExpr(GroupingExpr $expr);
    public function visitLiteralExpr(LiteralExpr $expr);
    public function visitUnaryExpr(UnaryExpr $expr);
}