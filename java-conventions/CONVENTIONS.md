## Coding conventions          
- always enclose code blocks in braces {} even if single line                                                                                                
- **always** prefer "var"                                                                                                                                    
- always prefer fluent style with streams instead of loops                                                                                                   
- prefer records for DTOs with lombok @Builder. use (toBuilder = true) when necessary                                                                        
- prefer Optional.ofNullable().map().orElse() for null checks instead of ternary operator                                                                    
- prefer StringUtils and CollectionUtils methods instead of OR conditions checking for null or empty for strings or lists                                    
                                                                                                                                                               
## Testing                                                                                                                                                   
- **NEVER** use lenient mode for mockito                                                                                                                     
- write tests for new code, make sure existing tests are passing.                                                                                            
- ensure 100% branch (condition) coverage for your tests. validate using jacoco report. 
