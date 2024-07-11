<?php

namespace Nkoll\Plox\Lox\Stmt;

use Nkoll\Plox\Lox\Expr\Expr;

class IfStmt extends Stmt
{
    /**
     * @param Expr $condition
     * @param Stmt $thenBranch
     * @param ?Stmt $elseBranch
     */
    public function __construct(
        public Expr $condition,
        public Stmt $thenBranch,
        public ?Stmt $elseBranch,
    ) { }

    public function accept(StmtVisitor $visitor)
    {
        return $visitor->visitIfStmt($this);
    }
}
