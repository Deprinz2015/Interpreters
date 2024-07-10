<?php

namespace Nkoll\Plox\Lox;

abstract class Expr
{
    abstract public function accept(Visitor $visitor);
}
