<?php

namespace Nkoll\Plox\Lox;

use IntlChar;
use Nkoll\Plox\PloxCommand;

class Scanner
{
    /** @var Token[] */
    private array $tokens = [];
    private string $source;

    private int $start = 0;
    private int $current = 0;
    private int $line = 1;

    private const array keywords = [
        "and" => TokenType::AND,
        "class" => TokenType::class,
        "else" => TokenType::ELSE,
        "false" => TokenType::FALSE,
        "for" => TokenType::FOR,
        "fun" => TokenType::FUN,
        "if" => TokenType::IF,
        "nil" => TokenType::NIL,
        "or" => TokenType::OR,
        "print" => TokenType::PRINT,
        "return" => TokenType::RETURN,
        "super" => TokenType::SUPER,
        "this" => TokenType::THIS,
        "true" => TokenType::TRUE,
        "var" => TokenType::VAR,
        "while" => TokenType::WHILE,
    ];

    public function __construct(string $source)
    {
        $this->source = $source;
    }

    /** @return Token[]  */
    public function scanTokens(): array
    {
        while(!$this->isAtEnd()) {
            $this->start = $this->current;
            $this->scanToken();
        }

        $this->tokens[] = new Token(TokenType::EOF, "", null, $this->line);
        return $this->tokens;
    }

    private function isAtEnd(): bool
    {
        return $this->current >= strlen($this->source);
    }

    private function scanToken(): void
    {
        $c = $this->advance();
        switch($c) {
            case '(':
                $this->addToken(TokenType::LEFT_PAREN);
                break;
            case ')':
                $this->addToken(TokenType::RIGHT_PAREN);
                break;
            case '{':
                $this->addToken(TokenType::LEFT_BRACE);
                break;
            case '}':
                $this->addToken(TokenType::RIGHT_BRACE);
                break;
            case ',':
                $this->addToken(TokenType::COMMA);
                break;
            case '.':
                $this->addToken(TokenType::DOT);
                break;
            case '-':
                $this->addToken(TokenType::MINUS);
                break;
            case '+':
                $this->addToken(TokenType::PLUS);
                break;
            case ';':
                $this->addToken(TokenType::SEMICOLON);
                break;
            case '*':
                $this->addToken(TokenType::STAR);
                break;
            case '!':
                $this->addToken($this->match('=') ? TokenType::BANG_EQUAL : TokenType::BANG);
                break;
            case '=':
                $this->addToken($this->match('=') ? TokenType::EQUAL_EQUAL : TokenType::EQUAL);
                break;
            case '<':
                $this->addToken($this->match('=') ? TokenType::LESS_EQUAL : TokenType::LESS);
                break;
            case '>':
                $this->addToken($this->match('=') ? TokenType::GREATER_EQUAL : TokenType::GREATER);
                break;
            case '/':
                if ($this->match('/')) {
                    while($this->peek() !== "\n" && !$this->isAtEnd()) {
                        $this->advance();
                    }
                    break;
                }
                $this->addToken(TokenType::SLASH);
                break;
            case ' ':
            case "\r":
            case "\t":
                // Ignore whitespace.
                break;
            case "\n":
                $this->line++;
                break;
            case '"':
                $this->string();
                break;
            default:
                if (IntlChar::isdigit($c)) {
                    $this->number();
                    break;
                } elseif (IntlChar::isalpha($c)) {
                    $this->identifier();
                    break;
                }
                PloxCommand::error($this->line, "Unexpected Character.");
        }
    }

    private function string(): void
    {
        while($this->peek() !== '"' && !$this->isAtEnd()) {
            if ($this->peek() === "\n") {
                $this->line++;
            }
            $this->advance();
        }

        if ($this->isAtEnd()) {
            PloxCommand::error($this->line, "Unterminated String.");
            return;
        }

        $this->advance();

        $value = $this->substr($this->source, $this->start + 1, $this->current - 1);
        $this->addToken(TokenType::STRING, $value);
    }

    private function number(): void
    {
        while(IntlChar::isdigit($this->peek())) {
            $this->advance();
        }

        if ($this->peek() === '.' && IntlChar::isdigit($this->peekNext())) {
            $this->advance();

            while(IntlChar::isdigit($this->peek())) {
                $this->advance();
            }
        }

        $value = floatval($this->substr($this->source, $this->start, $this->current));
        $this->addToken(TokenType::NUMBER, $value);
    }

    private function identifier(): void
    {
        while(IntlChar::isalnum($this->peek())) {
            $this->advance();
        }

        $value = $this->substr($this->source, $this->start, $this->current);
        $type = self::keywords[$value] ?? TokenType::IDENTIFIER;
        $this->addToken($type);
    }

    private function match(string $expected): bool
    {
        if ($this->isAtEnd()) {
            return false;
        }
        if ($this->source[$this->current] !== $expected) {
            return false;
        }

        $this->current++;
        return true;
    }

    private function peek(): string
    {
        if ($this->isAtEnd()) {
            return "\0";
        }
        return $this->source[$this->current];
    }

    private function peekNext(): string
    {
        if ($this->current + 1 >= strlen($this->source)) {
            return "\0";
        }
        return $this->source[$this->current + 1];
    }


    private function advance(): string
    {
        return $this->source[$this->current++];
    }

    private function addToken(TokenType $type, $literal = null): void
    {
        $text = $this->substr($this->source, $this->start, $this->current);
        $this->tokens[] = new Token($type, $text, $literal, $this->line);
    }

    private function substr(string $source, int $begin, int $end): string
    {
        return substr($source, $begin, $end - $begin);
    }

}
