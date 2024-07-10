<?php

namespace Nkoll\Plox\Lox\Expr;

class GroupingExpr extends Expr
{
    public function __construct(
        public Expr $expression,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitGroupingExpr($this);
    }
}
