/// ApolloVM Language Server — public API surface.
///
/// The runnable server lives in `bin/apollovm_lsp.dart`; this library exposes
/// the reusable analysis and transport pieces for embedding and testing.
library;

export 'src/analysis/analyzer.dart';
export 'src/analysis/document_store.dart';
export 'src/analysis/doc_extractor.dart';
export 'src/analysis/line_index.dart';
export 'src/analysis/symbols.dart';
export 'src/analysis/token_index.dart';
export 'src/protocol/protocol.dart';
export 'src/server/server.dart';
export 'src/transport/json_rpc.dart';
