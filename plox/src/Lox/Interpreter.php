<?php

namespace Nkoll\Plox\Lox;

use Nkoll\Plox\Lox\Error\RuntimeError;
use Nkoll\Plox\Lox\Expr\AssignExpr;
use Nkoll\Plox\Lox\Expr\BinaryExpr;
use Nkoll\Plox\Lox\Expr\CallExpr;
use Nkoll\Plox\Lox\Expr\Expr;
use Nkoll\Plox\Lox\Expr\ExprVisitor;
use Nkoll\Plox\Lox\Expr\GetExpr;
use Nkoll\Plox\Lox\Expr\GroupingExpr;
use Nkoll\Plox\Lox\Expr\LiteralExpr;
use Nkoll\Plox\Lox\Expr\LogicalExpr;
use Nkoll\Plox\Lox\Expr\SetExpr;
use Nkoll\Plox\Lox\Expr\SuperExpr;
use Nkoll\Plox\Lox\Expr\ThisExpr;
use Nkoll\Plox\Lox\Expr\UnaryExpr;
use Nkoll\Plox\Lox\Expr\VariableExpr;
use Nkoll\Plox\Lox\Stmt\BlockStmt;
use Nkoll\Plox\Lox\Stmt\ClassStmt;
use Nkoll\Plox\Lox\Stmt\ExpressionStmt;
use Nkoll\Plox\Lox\Stmt\FunctionStmt;
use Nkoll\Plox\Lox\Stmt\IfStmt;
use Nkoll\Plox\Lox\Stmt\ReturnStmt;
use Nkoll\Plox\Lox\Stmt\Stmt;
use Nkoll\Plox\Lox\Stmt\StmtVisitor;
use Nkoll\Plox\Lox\Stmt\VarStmt;
use Nkoll\Plox\Lox\Stmt\WhileStmt;
use Nkoll\Plox\PloxCommand;
use SplObjectStorage;

class Interpreter implements ExprVisitor, StmtVisitor
{
    private Environment $environment;
    public Environment $globals;

    private SplObjectStorage $locals;

    public function __construct()
    {
        $this->globals = new Environment();
        $this->environment = $this->globals;
        $this->locals = new SplObjectStorage();

        $this->globals->define("clock", NativeFunctions::clock());
        $this->globals->define("print", NativeFunctions::print($this));
        $this->globals->define("read", NativeFunctions::read());
    }

    /**
     * @param Stmt[] $statements
     * @return void
     */
    public function interpret(array $statements): void
    {
        try {
            foreach($statements as $stmt) {
                $this->execute($stmt);
            }
        } catch (RuntimeError $e) {
            PloxCommand::runtimeError($e);
        }
    }

    public function stringify($value): string
    {
        if ($value === null) {
            return 'nil';
        }

        if (is_float($value)) {
            $text = "$value";
            if (str_ends_with($text, ".0")) {
                $text = substr($text, 0, strlen($text) - 2);
            }
            return $text;
        }

        if (is_bool($value)) {
            return $value ? "true" : "false";
        }

        return "$value";
    }

    private function execute(Stmt $stmt)
    {
        $stmt->accept($this);
    }

    public function resolve(Expr $expr, int $depth)
    {
        $this->locals[$expr] = $depth;
    }

    public function executeBlock(array $statements, Environment $env)
    {
        $previous = $this->environment;

        try {
            $this->environment = $env;

            foreach($statements as $stmt) {
                $this->execute($stmt);
            }
        } finally {
            $this->environment = $previous;
        }
    }

    private function evaluate(Expr $expr)
    {
        return $expr->accept($this);
    }

    public function visitVarStmt(VarStmt $stmt)
    {
        $value = null;
        if ($stmt->initializer !== null) {
            $value = $this->evaluate($stmt->initializer);
        }

        $this->environment->define($stmt->name->lexeme, $value);
    }

    public function visitWhileStmt(WhileStmt $stmt)
    {
        while($this->evaluate($stmt->condition)) {
            $this->execute($stmt->body);
        }
    }

    public function visitExpressionStmt(ExpressionStmt $stmt)
    {
        $this->evaluate($stmt->expression);
    }

    public function visitFunctionStmt(FunctionStmt $stmt)
    {
        $function = new LoxFunction($stmt, $this->environment, false);
        $this->environment->define($stmt->name->lexeme, $function);
    }

    public function visitIfStmt(IfStmt $stmt)
    {
        if ($this->evaluate($stmt->condition)) {
            $this->execute($stmt->thenBranch);
        } elseif ($stmt->elseBranch) {
            $this->execute($stmt->elseBranch);
        }
    }

    public function visitReturnStmt(ReturnStmt $stmt)
    {
        $value = null;
        if ($stmt->value) {
            $value = $this->evaluate($stmt->value);
        }

        throw new ReturnValue($value);
    }

    public function visitBlockStmt(BlockStmt $stmt)
    {
        $this->executeBlock($stmt->statements, new Environment($this->environment));
    }

    public function visitClassStmt(ClassStmt $stmt)
    {
        $superclass = null;
        if ($stmt->superclass) {
            $superclass = $this->evaluate($stmt->superclass);
            if (!$superclass instanceof LoxClass) {
                throw new RuntimeError($stmt->superclass->name, "Superclass must be a class.");
            }
        }

        $this->environment->define($stmt->name->lexeme, null);

        if ($stmt->superclass) {
            $this->environment = new Environment($this->environment);
            $this->environment->define("super", $superclass);
        }

        $methods = [];
        foreach ($stmt->methods as $method) {
            $function = new LoxFunction($method, $this->environment, $method->name->lexeme === "init");
            $methods[$method->name->lexeme] = $function;
        }

        $klass = new LoxClass($stmt->name->lexeme, $superclass, $methods);

        if ($stmt->superclass) {
            $this->environment = $this->environment->enclosing;
        }

        $this->environment->assign($stmt->name, $klass);
    }

    public function visitAssignExpr(AssignExpr $expr)
    {
        $value = $this->evaluate($expr->value);

        $distance = $this->locals[$expr] ?? null;
        if ($distance !== null) {
            $this->environment->assignAt($distance, $expr->name, $value);
        } else {
            $this->globals->assign($expr->name, $value);
        }
        return $value;
    }

    public function visitVariableExpr(VariableExpr $expr)
    {
        return $this->lookupVariable($expr->name, $expr);
    }

    private function lookupVariable(Token $name, Expr $expr): mixed
    {
        $distance = $this->locals[$expr] ?? null;
        if ($distance !== null) {
            return $this->environment->getAt($distance, $name->lexeme);
        }

        return $this->globals->get($name);
    }

    public function visitBinaryExpr(BinaryExpr $expr)
    {
        $left = $this->evaluate($expr->left);
        $right = $this->evaluate($expr->right);

        switch ($expr->operator->type) {
            case TokenType::GREATER:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left > (float)$right;
            case TokenType::GREATER_EQUAL:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left >= (float)$right;
            case TokenType::LESS:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left < (float)$right;
            case TokenType::LESS_EQUAL:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left <= (float)$right;
            case TokenType::EQUAL_EQUAL:
                return $left === $right;
            case TokenType::BANG_EQUAL:
                return $left !== $right;

            case TokenType::MINUS:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left - (float)$right;

            case TokenType::PLUS:
                if (is_double($left) && is_double($right)) {
                    return $left + $right;
                }

                if (is_string($left) || is_string($right)) {
                    return "$left$right";
                }

                throw new RuntimeError($expr->operator, "Operands must be two numbers or two string.");
                break;

            case TokenType::SLASH:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left / (float)$right;

            case TokenType::STAR:
                $this->checkNumberOperands($expr->operator, $left, $right);
                return (float)$left * (float)$right;
        }
    }

    public function visitCallExpr(CallExpr $expr)
    {
        $callee = $this->evaluate($expr->callee);

        $args = [];
        foreach($expr->arguments as $argument) {
            $args[] = $this->evaluate($argument);
        }

        if(!$callee instanceof LoxCallable) {
            throw new RuntimeError($expr->paren, "Can only call functions and classes.");
        }
        $argCount = count($args);
        if ($argCount !== $callee->arity()) {
            throw new RuntimeError($expr->paren, "Expected {$callee->arity()} arguments but got $argCount.");
        }
        return $callee->call($this, $args);
    }

    public function visitGetExpr(GetExpr $expr)
    {
        $object = $this->evaluate($expr->object);
        if ($object instanceof LoxInstance) {
            return $object->get($expr->name);
        }

        throw new RuntimeError($expr->name, "Only instances have properties.");
    }

    public function visitGroupingExpr(GroupingExpr $expr)
    {
        return $this->evaluate($expr->expression);
    }

    public function visitLiteralExpr(LiteralExpr $expr)
    {
        return $expr->value;
    }

    public function visitLogicalExpr(LogicalExpr $expr)
    {
        $left = $this->evaluate($expr->left);

        if ($expr->operator->type === TokenType::OR) {
            if ($left) {
                return $left;
            }
        } else {
            if (!$left) {
                return $left;
            }
        }

        return $this->evaluate($expr->right);
    }

    public function visitSetExpr(SetExpr $expr)
    {
        $obj = $this->evaluate($expr->object);

        if (!$obj instanceof LoxInstance) {
            throw new RuntimeError($expr->name, "Only instances have fields.");
        }

        $value = $this->evaluate($expr->value);
        $obj->set($expr->name, $value);
        return $value;
    }

    public function visitSuperExpr(SuperExpr $expr)
    {
        $distance = $this->locals[$expr];
        /** @var LoxClass */
        $superclass = $this->environment->getAt($distance, "super");

        $object = $this->environment->getAt($distance - 1, "this");

        $method = $superclass->findMethod($expr->method->lexeme);

        if (!$method) {
            throw new RuntimeError($expr->method, "Undefined property '{$expr->method->lexeme}'.");
        }

        return $method->bind($object);
    }

    public function visitThisExpr(ThisExpr $expr)
    {
        return $this->lookupVariable($expr->keyword, $expr);
    }

    public function visitUnaryExpr(UnaryExpr $expr)
    {
        $right = $this->evaluate($expr->right);

        switch ($expr->operator->type) {
            case TokenType::MINUS:
                $this->checkNumberOperand($expr->operator, $right);
                return -(float)$right;
            case TokenType::BANG:
                return !$right;
        }

        return null;
    }

    private function checkNumberOperand(Token $op, $operand): void
    {
        if (is_float($operand)) {
            return;
        }

        throw new RuntimeError($op, "Operand must be a number.");
    }

    private function checkNumberOperands(Token $op, $left, $right): void
    {
        if (is_float($left) && is_float($right)) {
            return;
        }

        throw new RuntimeError($op, "Operands must be a number.");
    }

}
