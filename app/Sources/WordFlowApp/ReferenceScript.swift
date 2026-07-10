// The fixed 20-sentence reference script the accuracy harness scores against
// (AC-9.5), kept in step with fixtures/reference_script.txt so the app can show
// it and send it as the reference text without reading a repo file.

enum ReferenceScript {
    static let sentences: [String] = [
        "The quarterly review is scheduled for Thursday afternoon.",
        "Please send the updated figures to the finance team by noon.",
        "I think we should prioritise the onboarding flow this sprint.",
        "Can you double check the colour scheme on the settings page?",
        "The meeting ran long, so we moved the demo to next week.",
        "Our largest client asked for a summary of the changes.",
        "Let us organise the files before the audit begins.",
        "The new microphone sounds much clearer than the old one.",
        "Remember to book the venue and confirm the catering.",
        "She recognised the pattern almost immediately.",
        "The report analyses three years of sales data.",
        "We travelled to Manchester for the workshop on Tuesday.",
        "His neighbour offered to water the plants while he was away.",
        "The centre of the diagram shows the main data flow.",
        "I apologise for the delay in getting back to you.",
        "Kubernetes handles the container orchestration for us.",
        "Let us catalogue every request before we prioritise them.",
        "The behaviour of the model improved after the last update.",
        "Please transcribe the interview and share the notes.",
        "That is everything for today, thanks for your time.",
    ]

    static var text: String { sentences.joined(separator: " ") }
}
