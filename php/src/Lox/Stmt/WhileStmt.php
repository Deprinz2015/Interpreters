<?php

namespace Nkoll\Plox\Lox\Stmt;

use Nkoll\Plox\Lox\Expr\Expr;

class WhileStmt extends Stmt
{
    /**
     * @param Expr $condition
     * @param Stmt $body
     */
    public function __construct(
        public Expr $condition,
        public Stmt $body,
    ) { }

    public function accept(StmtVisitor $visitor)
    {
        return $visitor->visitWhileStmt($this);
    }
}
