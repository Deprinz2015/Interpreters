<?php

namespace Nkoll\Plox\Lox\Expr;

class LiteralExpr extends Expr
{
    public function __construct(
        public mixed $value,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitLiteralExpr($this);
    }
}
