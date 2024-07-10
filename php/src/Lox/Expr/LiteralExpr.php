<?php

namespace Nkoll\Plox\Lox\Expr;

class LiteralExpr extends Expr
{
    /**
     * @param mixed $value
     */
    public function __construct(
        public mixed $value,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitLiteralExpr($this);
    }
}
