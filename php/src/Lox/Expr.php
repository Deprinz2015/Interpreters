<?php

namespace Nkoll\Plox\Lox;

abstract class Expr
{
    abstract public function accept(Visitor $visitor);
}

interface Visitor
{
    public function visitBinaryExpr(Binary $expr);
    public function visitGroupingExpr(Grouping $expr);
    public function visitLiteralExpr(Literal $expr);
    public function visitUnaryExpr(Unary $expr);
}
class Binary extends Expr
{
    public function __construct(
        public Expr $left,
        public Token $operator,
        public Expr $right,
    ) { }

    public function accept(Visitor $visitor)
    {
        return $visitor->visitBinaryExpr($this);
    }
}

class Grouping extends Expr
{
    public function __construct(
        public Expr $expression,
    ) { }

    public function accept(Visitor $visitor)
    {
        return $visitor->visitGroupingExpr($this);
    }
}

class Literal extends Expr
{
    public function __construct(
        public mixed $value,
    ) { }

    public function accept(Visitor $visitor)
    {
        return $visitor->visitLiteralExpr($this);
    }
}

class Unary extends Expr
{
    public function __construct(
        public Token $operator,
        public Expr $right,
    ) { }

    public function accept(Visitor $visitor)
    {
        return $visitor->visitUnaryExpr($this);
    }
}
