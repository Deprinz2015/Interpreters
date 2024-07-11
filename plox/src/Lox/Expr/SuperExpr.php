<?php

namespace Nkoll\Plox\Lox\Expr;

use Nkoll\Plox\Lox\Token;

class SuperExpr extends Expr
{
    /**
     * @param Token $keyword
     * @param Token $method
     */
    public function __construct(
        public Token $keyword,
        public Token $method,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitSuperExpr($this);
    }
}
