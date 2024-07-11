<?php

namespace Nkoll\Plox\Lox\Expr;

abstract class Expr
{
    abstract public function accept(ExprVisitor $visitor);
}
