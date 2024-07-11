<?php

namespace Nkoll\Plox\Lox;

enum FunctionType 
{
    case NONE;
    case FUNCTION;
    case INITIALIZER;
    case METHOD;
}
