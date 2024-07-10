<?php

namespace Nkoll\Plox\Lox\Stmt;

use Nkoll\Plox\Lox\Expr;

class ExpressionStmt extends Stmt
{
    public function __construct(
        public Expr $expression,
    ) { }

    public function accept(StmtVisitor $visitor)
    {
        return $visitor->visitExpressionStmt($this);
    }
}
