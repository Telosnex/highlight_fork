// Port of vendor/highlightjs-solidity/solidity.js (ed34915).
// Kept as a factory: compiled modes must not be shared between Highlight engines.
import '../highlight_core.dart';

Mode solidity(Highlight hljs) {
  const lexemes = r'[A-Za-z_$][A-Za-z_$0-9]*|\*';
  final types = <String>[
    'var',
    'bool',
    'string',
    'int',
    'uint',
    'byte',
    'bytes',
    'fixed',
    'ufixed',
    'address',
  ];
  for (var size = 1; size <= 32; size++) {
    types.addAll(['bytes$size', 'int${size * 8}', 'uint${size * 8}']);
    for (var precision = 0; precision <= 80; precision++) {
      types.addAll([
        'fixed${size * 8}x$precision',
        'ufixed${size * 8}x$precision',
      ]);
    }
  }
  final keywords = <String, dynamic>{
    r'$pattern': lexemes,
    'keyword':
        '${types.join(' ')} enum struct mapping new delete if else for '
        'while continue break return throw emit try catch _ function modifier '
        'event error constructor fallback receive virtual override constant '
        'immutable anonymous indexed storage memory calldata external public '
        'internal payable pure view private returns import from as using pragma '
        'contract interface library is abstract assembly unchecked',
    'literal':
        'true false wei szabo finney ether seconds minutes hours days weeks years',
    'built_in':
        'self this super selfdestruct suicide now msg block tx abi type '
        'blockhash gasleft assert revert require Error sha3 sha256 keccak256 '
        'ripemd160 ecrecover addmod mulmod log0 log1 log2 log3 log4 send transfer '
        'call callcode delegatecall staticcall',
  };
  // Coloring and detection relevance are separate: generic C/JS keywords and
  // parameterized types must not make unrelated source look like Solidity.
  const distinctive = {
    'mapping',
    'modifier',
    'event',
    'fallback',
    'receive',
    'virtual',
    'override',
    'immutable',
    'indexed',
    'storage',
    'calldata',
    'payable',
    'pure',
    'view',
    'returns',
    'pragma',
    'contract',
    'interface',
    'library',
    'assembly',
    'wei',
    'szabo',
    'finney',
    'ether',
    'msg',
    'abi',
    'selfdestruct',
    'gasleft',
    'keccak256',
    'ecrecover',
  };
  for (final scope in ['keyword', 'literal', 'built_in']) {
    keywords[scope] = (keywords[scope] as String)
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => '$word|${distinctive.contains(word) ? 1 : 0}')
        .join(' ');
  }
  final number = Mode(
    scope: 'number',
    relevance: 0,
    begin:
        r'-?((?<!\$)\b0[xX]([a-fA-F0-9]_?)*[a-fA-F0-9]|((?<!\$)\b[1-9](_?\d)*(\.((\d_?)*\d)?)?|\.\d(_?\d)*)([eE][-+]?\d(_?\d)*)?|(?<!\$)\b0)',
  );
  final hexString = Mode(
    scope: 'string',
    variants: [
      Mode(begin: r"hex'", end: "'"),
      Mode(begin: 'hex"', end: '"'),
    ],
    relevance: 0,
  );
  final literals = <dynamic>[
    hexString,
    hljs.APOS_STRING_MODE,
    hljs.QUOTE_STRING_MODE,
    hljs.C_LINE_COMMENT_MODE,
    hljs.C_BLOCK_COMMENT_MODE,
    number,
  ];
  final params = Mode(
    scope: 'params',
    begin: r'\(',
    end: r'\)',
    excludeBegin: true,
    excludeEnd: true,
    keywords: keywords,
    contains: [...literals, 'self'],
    relevance: 0,
  );
  final title = Mode(
    scope: 'title',
    begin: r'[A-Za-z$_][0-9A-Za-z$_]*',
    keywords: keywords,
    relevance: 0,
  );
  final members = Mode(
    begin: r'\.\s*',
    end: r'[^A-Za-z0-9$_\.]',
    excludeBegin: true,
    excludeEnd: true,
    keywords: {
      'built_in':
          'gas value selector address send transfer call '
                  'callcode delegatecall staticcall balance length push pop name '
                  'creationCode runtimeCode'
              .split(' ')
              .map((w) => '$w|0')
              .join(' '),
    },
    relevance: 0,
  );
  Mode properties(String object, String properties) => Mode(
    begin: '(?<!\\\$)\\b$object\\.\\s*',
    end: r'[^A-Za-z0-9$_\.]',
    excludeEnd: true,
    keywords: {
      r'$pattern': lexemes,
      'built_in': '$object $properties'.split(' ').map((w) => '$w|0').join(' '),
    },
    contains: [members],
    relevance: 0,
  );
  final assemblyKeywords = {
    r'$pattern': r'[A-Za-z_$][A-Za-z_$0-9.]*',
    'keyword':
        'assembly let if switch case default for leave jump jumpi stop '
        'return revert selfdestruct invalid',
    'built_in':
        'add sub mul div sdiv mod smod exp not lt gt slt sgt eq iszero '
        'and or xor byte shl shr sar addmod mulmod signextend keccak256 pc pop '
        '${List.generate(16, (i) => 'dup${i + 1} swap${i + 1}').join(' ')} '
        'mload mstore mstore8 sload sstore msize gas address balance selfbalance '
        'caller callvalue calldataload calldatasize calldatacopy codesize '
        'codecopy extcodesize extcodecopy returndatasize returndatacopy '
        'extcodehash create create2 call callcode delegatecall staticcall '
        'log0 log1 log2 log3 log4 chainid origin gasprice blockhash coinbase '
        'timestamp number difficulty prevrandao gaslimit basefee',
  };
  final assemblyMembers = Mode(
    begin: '_',
    end: r'[^A-Za-z0-9$.]',
    excludeBegin: true,
    excludeEnd: true,
    keywords: {'built_in': 'slot offset'},
    relevance: 0,
  );
  final assemblyBlock = Mode(
    begin: r'\{',
    end: r'\}',
    keywords: assemblyKeywords,
    contains: [...literals, assemblyMembers, 'self'],
  );
  return Mode(
    name: 'Solidity',
    aliases: ['sol'],
    keywords: keywords,
    illegal: '#',
    contains: [
      ...literals,
      Mode(
        scope: 'function',
        relevance: 0,
        beginKeywords:
            'function modifier event error constructor fallback receive',
        end: r'[{;]',
        excludeEnd: true,
        illegal: '%',
        keywords: keywords,
        contains: [
          title,
          params,
          hljs.C_LINE_COMMENT_MODE,
          hljs.C_BLOCK_COMMENT_MODE,
        ],
      ),
      properties('msg', 'gas value data sender sig'),
      properties(
        'block',
        'blockhash coinbase difficulty prevrandao gaslimit number timestamp basefee chainid',
      ),
      properties('tx', 'gasprice origin'),
      properties(
        'abi',
        'decode encode encodePacked encodeWithSelector encodeWithSignature encodeCall',
      ),
      members,
      Mode(
        scope: 'class',
        relevance: 3,
        beginKeywords: 'contract interface library',
        end: r'\{',
        excludeEnd: true,
        illegal: r'[:"\[\]]',
        keywords: keywords,
        contains: [
          Mode(beginKeywords: 'is'),
          title,
          params,
          hljs.C_LINE_COMMENT_MODE,
          hljs.C_BLOCK_COMMENT_MODE,
        ],
      ),
      Mode(
        beginKeywords: 'struct enum',
        end: r'\{',
        excludeEnd: true,
        illegal: r'[:"\[\]]',
        keywords: keywords,
        contains: [title, hljs.C_LINE_COMMENT_MODE, hljs.C_BLOCK_COMMENT_MODE],
      ),
      Mode(
        beginKeywords: 'import',
        relevance: 0,
        end: ';',
        keywords: {r'$pattern': lexemes, 'keyword': 'import|0 *|0 from|0 as|0'},
        contains: [title, ...literals],
      ),
      Mode(
        beginKeywords: 'using',
        end: ';',
        keywords: {r'$pattern': lexemes, 'keyword': 'using * for'},
        contains: [title, hljs.C_LINE_COMMENT_MODE, hljs.C_BLOCK_COMMENT_MODE],
      ),
      Mode(
        scope: 'meta',
        beginKeywords: 'pragma',
        end: ';',
        keywords: {
          'keyword': 'pragma solidity experimental',
          'built_in': 'ABIEncoderV2 SMTChecker',
        },
        contains: [
          hljs.C_LINE_COMMENT_MODE,
          hljs.C_BLOCK_COMMENT_MODE,
          hljs.APOS_STRING_MODE.copyWith(scope: 'string'),
          hljs.QUOTE_STRING_MODE.copyWith(scope: 'string'),
        ],
      ),
      Mode(
        beginKeywords: 'assembly',
        end: r'\b\B',
        contains: [
          hljs.C_LINE_COMMENT_MODE,
          hljs.C_BLOCK_COMMENT_MODE,
          Mode(
            begin: r'\{',
            end: r'\}',
            endsParent: true,
            keywords: assemblyKeywords,
            contains: [...literals, assemblyMembers, assemblyBlock],
          ),
        ],
      ),
    ],
  );
}
