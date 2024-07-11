<?php

namespace Nkoll\Plox\Lox\Expr;

use Nkoll\Plox\Lox\Token;

class GetExpr extends Expr
{
    /**
     * @param Expr $object
     * @param Token $name
     */
    public function __construct(
        public Expr $object,
        public Token $name,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitGetExpr($this);
    }
}
