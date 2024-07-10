<?php

namespace Nkoll\Plox\Lox\Stmt;

interface StmtVisitor
{
    public function visitExpressionStmt(ExpressionStmt $stmt);
    public function visitPrintStmt(PrintStmt $stmt);
}