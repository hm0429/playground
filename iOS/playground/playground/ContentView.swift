//
//  ContentView.swift
//  playground
//
//  Created by Hideyoshi Moriya on 2024/07/13.
//

import SwiftUI

struct ContentView: View {
    @State var showSheet = false
    
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            Button(action: {
                showSheet.toggle()
            }, label: {
                Text("今日の運勢は")
            })
            .sheet(isPresented: $showSheet){
                ResultView()
            }
        }
        .padding()
    }
}

struct ResultView: View {
    var body: some View {
        if let unsei = ["ラーメン食べていい！", "大吉", "中吉", "吉"].randomElement() {
            Text(unsei)
        }
    }
}

#Preview {
    ContentView()
}
