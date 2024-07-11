<?php

namespace Nkoll\Plox\Lox\Stmt;

abstract class Stmt
{
    abstract public function accept(StmtVisitor $visitor);
}
