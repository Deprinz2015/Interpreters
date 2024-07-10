<?php

namespace Nkoll\Plox\Lox;

class LiteralExpr extends Expr
{
    public function __construct(
        public mixed $value,
    ) { }

    public function accept(Visitor $visitor)
    {
        return $visitor->visitLiteralExpr($this);
    }
}
