<?php

namespace Nkoll\Plox\Lox;

use Nkoll\Plox\Lox\LoxType\LoxCallable;

class NativeFunctions
{
    public static function clock()
    {
        return self::produceLoxCallable(0, function () {
            return microtime(true);
        });
    }

    public static function print()
    {
        return self::produceLoxCallable(1, function(Interpreter $interpreter, array $argument) {
            echo $interpreter->stringify($argument[0]) . PHP_EOL;
        });
    }

    public static function read()
    {
        return self::produceLoxCallable(1, function (Interpreter $interpreter, array $arguments) {
            $input = readline($arguments[0]);
            if (is_numeric($input)) {
                return floatval($input);
            }

            return $input;
        });
    }

    private static function produceLoxCallable(int $arity, $call, ...$arguments)
    {
        return new class($arity, $call, $arguments) implements LoxCallable {
            public function __construct(
                private int $arity,
                private $callFunc,
                private array $arguments,
            ) {
            }

            public function arity(): int
            {
                return $this->arity;
            }

            public function call(Interpreter $interpreter, array $arguments)
            {
                $call = $this->callFunc;

                return $call($interpreter, $arguments, $this->arguments);
            }

            public function __toString()
            {
                return '<native fn>';
            }
        };
    }
}
