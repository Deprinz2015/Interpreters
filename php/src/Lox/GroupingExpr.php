<?php

namespace Nkoll\Plox\Lox;

class GroupingExpr extends Expr
{
    public function __construct(
        public Expr $expression,
    ) { }

    public function accept(Visitor $visitor)
    {
        return $visitor->visitGroupingExpr($this);
    }
}
