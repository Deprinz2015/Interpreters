<?php

namespace Nkoll\Plox\Lox\Expr;

use Nkoll\Plox\Lox\Token;

class SetExpr extends Expr
{
    /**
     * @param Expr $object
     * @param Token $name
     * @param Expr $value
     */
    public function __construct(
        public Expr $object,
        public Token $name,
        public Expr $value,
    ) { }

    public function accept(ExprVisitor $visitor)
    {
        return $visitor->visitSetExpr($this);
    }
}
