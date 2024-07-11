<?php

namespace Nkoll\Plox\Lox\Stmt;

interface StmtVisitor
{
    public function visitBlockStmt(BlockStmt $stmt);
    public function visitClassStmt(ClassStmt $stmt);
    public function visitExpressionStmt(ExpressionStmt $stmt);
    public function visitFunctionStmt(FunctionStmt $stmt);
    public function visitIfStmt(IfStmt $stmt);
    public function visitReturnStmt(ReturnStmt $stmt);
    public function visitVarStmt(VarStmt $stmt);
    public function visitWhileStmt(WhileStmt $stmt);
}