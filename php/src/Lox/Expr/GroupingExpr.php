<?php

namespace Nkoll\Plox\Lox\Expr;

class GroupingExpr extends Expr
{
    /**
     * @param Expr $expression
     */
    public function __construct(
        public Expr $expression,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitGroupingExpr($this);
    }
}
