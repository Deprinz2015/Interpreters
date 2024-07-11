<?php

namespace Nkoll\Plox\Lox\Expr;

use Nkoll\Plox\Lox\Token;

class LogicalExpr extends Expr
{
    /**
     * @param Expr $left
     * @param Token $operator
     * @param Expr $right
     */
    public function __construct(
        public Expr $left,
        public Token $operator,
        public Expr $right,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitLogicalExpr($this);
    }
}
