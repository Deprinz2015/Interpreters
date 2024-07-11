<?php

namespace Nkoll\Plox\Lox\Expr;

interface ExprVisitor
{
    public function visitAssignExpr(AssignExpr $expr);
    public function visitBinaryExpr(BinaryExpr $expr);
    public function visitCallExpr(CallExpr $expr);
    public function visitGetExpr(GetExpr $expr);
    public function visitSetExpr(SetExpr $expr);
    public function visitSuperExpr(SuperExpr $expr);
    public function visitThisExpr(ThisExpr $expr);
    public function visitGroupingExpr(GroupingExpr $expr);
    public function visitLiteralExpr(LiteralExpr $expr);
    public function visitLogicalExpr(LogicalExpr $expr);
    public function visitUnaryExpr(UnaryExpr $expr);
    public function visitVariableExpr(VariableExpr $expr);
}