<?php

namespace Nkoll\Plox\Lox\Stmt;

use Nkoll\Plox\Lox\Expr\Expr;

class PrintStmt extends Stmt
{
    /**
     * @param Expr $expression
     */
    public function __construct(
        public Expr $expression,
    ) { }

    public function accept(StmtVisitor $visitor)
    {
        return $visitor->visitPrintStmt($this);
    }
}
